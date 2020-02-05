#                                                                         #
#    ▄▄▄█████▓▓█████ ▄▄▄       ███▄ ▄███▓          ██▓ ▄████▄  ▓█████     #
#    ▓  ██▒ ▓▒▓█   ▀▒████▄    ▓██▒▀█▀ ██▒         ▓██▒▒██▀ ▀█  ▓█   ▀     #
#    ▒ ▓██░ ▒░▒███  ▒██  ▀█▄  ▓██    ▓██░         ▒██▒▒▓█    ▄ ▒███       #
#    ░ ▓██▓ ░ ▒▓█  ▄░██▄▄▄▄██ ▒██    ▒██          ░██░▒▓▓▄ ▄██▒▒▓█  ▄     #
#      ▒██▒ ░ ░▒████▒▓█   ▓██▒▒██▒   ░██▒         ░██░▒ ▓███▀ ░░▒████▒    #
#      ▒ ░░   ░░ ▒░ ░▒▒   ▓▒█░░ ▒░   ░  ░         ░▓  ░ ░▒ ▒  ░░░ ▒░ ░    #
#        ░     ░ ░  ░ ▒   ▒▒ ░░  ░      ░          ▒ ░  ░  ▒    ░ ░  ░    #
#      ░         ░    ░   ▒   ░      ░             ▒ ░░           ░       #
#                ░ OFX INFRASTRUCTURE & CLOUD ENGINEERING         ░  ░    #
#                                                                         #                                                        
<#          
.DESCRIPTION
  <Deploys Customer Gateways and VPN Connections >>for use in master account<<
.INPUTS
  ./variables.ps1
  <aws exports> -- transit gateway stack name 
 # Files
  ./files/customer-gateway-source.yaml"
.OUTPUTS
  <./files/attachment.yaml>
.NOTES
  Author: Fraser Elliot Carter Smith
#>

#variables
$cleanupmode = $false #<--- if true, script will delete all failed stacks only!
#<-- edit .variables.ps1 !!!!

#fixed variables
$variables = . "./variables.ps1"
$yamltemplate= "./files/customer-gateway-source.yaml"
$ip=6 #<-- warning 1-5 is reserved by aws for octect tunnel inside ip 3rd octet

Write-Host "Preparing Files"
$sites = @( 
    [PSCustomObject]@{site="syd"; network="10.0.0.0/16"; asn="65000"; endpoints=@("49.255.71.2","14.202.31.162")},
    [PSCustomObject]@{site="lon"; network="10.2.0.0/16"; asn="65002"; endpoints=@("80.169.133.98","167.98.115.234")},
    [PSCustomObject]@{site="sfo"; network="10.4.0.0/16"; asn="65004"; endpoints=@("4.14.110.226","12.205.169.10")},
    [PSCustomObject]@{site="tor"; network="10.6.0.0/16"; asn="65006"; endpoints=@("172.110.66.2")},
    [PSCustomObject]@{site="hkg"; network="10.8.0.0/16"; asn="65008"; endpoints=@("203.198.186.225","118.143.126.211")}
) 

Write-Host "" ; Write-Host "--------------------------------------" -f black -b green
Write-Host " Deploying Customer Gateways and VPN. " -f black -b green
Write-Host "--------------------------------------" -f black -b green ; Write-Host "" ; Write-Host ""

#Create Customer Gateways
try { $tgwid = (Get-CFNExport -region $region | ? Name -like $tgwstackname).Value}
catch { Write-Host "Transit Gateway stack does not exist, ending script" -f red ; break } #checks if pre-requisite transit gateway cf deployemnt exists and breaks script if not.

foreach($s in $sites){
  $x=0
  $endpoints = $s.endpoints
  $site = $s.site
  $network = $s.network
  $asn = $s.asn
  
    Write-Host "Processing" -f black -b white 
    foreach($e in $endpoints){
      $x=$x+1 ; $stack = 0 ; $stackstatus = 0
      $stackname = "$projectname-$site-0$x"
      $vpnconnection ="vpn-$stackname"
      $cgwfile = "./files/customer-gateway-$site.yaml"
      $infile = $yamltemplate
      $outfile = ".\files\$stackname.yaml"
      $endpoint = $e
      
      # Cleanup 
      #if($cleanupmode -eq $true){ $cleanupscript = . "./files/cleanup.ps1" ; $cleanupscript ; Remove-Item $outfile -ErrorAction SilentlyContinue -force ; continue }

      
      # Regex query to pull 2nd octet from network and use in addition to base $ip value 3rd octet to enforce ip scheme.
      $regex = "\.(\d)\."
      $network -match $regex 
      $ip=$ip+1 ; $ip=$ip+$matches[1]
      # Construct tunnel inside /30 ip address # 3rd octet must be between 6 and 168
      $tunnelinside01 = "169.254."+$ip+".0/30"
      $tunnelinside02 = "169.254."+$ip+".4/30"

      # Construct .yaml cf deployment file using regex queries.
      Write-Host "" ; Write-Host "Building $outfile file" -f green ; Write-Host ""
      (Get-Content $infile) | Foreach-Object {
          $_ -replace("regexvpntype",$vpntype) `
            -replace("regextgwid",$tgwid) `
            -replace("regexcgw",$stackname) `
            -replace("regexbgpasn",$asn) `
            -replace("regexendpoint",$endpoint) `
            -replace("regextunnelinside01",$tunnelinside01) `
            -replace("regextunnelinside02",$tunnelinside02) `
            -replace("regexvpnconnection",$vpnconnection)
          } | Set-Content $outfile -force     

      $error.clear()
      Write-host "Validating CF Template" -f yellow -b magenta
      Test-CFNTemplate -templateBody (Get-Content $outfile -raw) -Region $region
      if($error.count -gt 0){Write-Host "Error Validation Failure!" -f white -b red ; Write-Host "" ;  continue } # attempts to validate the CF template.
      if($error.count -eq 0){Write-Host "Template is Valid" -f black -b green ; Write-Host "" }
      try { $stackstatus = ((Get-CFNStack -Stackname $stackname -region $region).StackStatus) }
      catch { $stack = 1 ; Write-Host "Stack does not exist!" -f yellow } # set stack value to 1 if first deployment
  
      if($stack -eq 0){
          # If stack exists, get the stack deployment status and check against google values
          # If match , set stack value to 0 -> skip iteration, else set stack value to 2.
          $goodvalues = @("CREATE_COMPLETE","CREATE_IN_PROGRESS")
          foreach($v in $goodvalues){if($v -eq $stackstatus){ $stack = 0 ; break } else { $stack = 2 } }
      if($stack -eq 0){ 
          # Stack already deployed or in process of being deployed
          Write-Host "Existing Stack Status:" -f yellow -b magenta -NoNewLine ; 
          Write-Host " $stackstatus... Skipping." ; continue } # stack deployment already in progress, skip iteration
          }
      if($stack -eq 2){
          # Stack exists in bad state ->>> Delete it 
          Write-Host "Removing Failed Stack" -f cyan
          Remove-CFNStack -Stackname $stackname -region $region -force  
          Wait-CFNStack -Stackname $stackname -region $region
          } 
      if($stack -ge 1){  
          # Create Stack if $stack = 1 or more
          Write-Host "Creating Stack" -f black -b cyan
          New-CFNStack -StackName $stackname -TemplateBody (Get-Content $outfile -raw) -Region $region
          
          Remove-Item $outfile -force -Erroraction SilentlyContinue
          }
      Write-Host ""
      }
    }

Write-Host "" ; Write-Host "---------------------------" -f black -b green
Write-Host "Script Processing Complete." -f black -b green
Write-Host "---------------------------" -f black -b green ; Write-Host ""