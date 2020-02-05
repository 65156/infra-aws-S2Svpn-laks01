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
  <Deploys Customer Gateways in Master Account and Peering>
.INPUTS
  <aws exports> -- transit gateway stack name 
 # Files
  ./files/customer-gateway-source.yaml"
.OUTPUTS
  <./files/attachment.yaml>
.NOTES
  Author: Fraser Elliot Carter Smith
#>

#configurable variables
$projectname = "cgw" #<--- becomes the prefix for all cgw stack names and vpn connection stacknames 
$uuid = 'laks01'
$region = "ap-southeast-2"
$vpntype = 'ipsec.1'
$presharekey = "testpassword000001x"
$transitgatewaystackname = "transit-gateway" # must reference the stackname of the transit gateway cf stack for export referencing!

#fixed variables
$yamltemplate= "./files/customer-gateway-source.yaml"
$ip=5 

Write-Host "Preparing Files"
$sites = @( 
    [PSCustomObject]@{site="syd"; network="10.0.0.0/16"; asn="65000"; cgw = ""; endpoints=@("49.255.71.2","14.202.31.162")},
    [PSCustomObject]@{site="lon"; network="10.2.0.0/16"; asn="65002"; cgw = ""; endpoints=@("80.169.133.98","167.98.115.234")},
    [PSCustomObject]@{site="sfo"; network="10.4.0.0/16"; asn="65004"; cgw = ""; endpoints=@("4.14.110.226","12.205.169.10")},
    [PSCustomObject]@{site="tor"; network="10.6.0.0/16"; asn="65006"; cgw = ""; endpoints=@("172.110.66.2")},
    [PSCustomObject]@{site="hkg"; network="10.8.0.0/16"; asn="65008" ; cgw = "" ; endpoints=@("203.198.186.225","118.143.126.211")}
) 

Write-Host ""
Write-Host "--------------------------------------" -f black -b green
Write-Host " Deploying Customer Gateways and VPN. " -f black -b green
Write-Host "--------------------------------------" -f black -b green
Write-Host ""
Write-Host ""

#Create Customer Gateways
try { $transitgatewayid = (Get-CFNExport -region $region | ? Name -like $transitgatewaystackname).Value}
catch { Write-Host "Transit Gateway stack does not exist, ending script" -f red ; break } #checks if pre-requisite transit gateway cf deployemnt exists and breaks script if not.

foreach($s in $sites){
  $x=0
  $endpoints = $s.endpoints
  $site = $s.site
  $network = $s.network
  $asn = $s.asn
  $cgw = $s.cgw
  
    Write-Host "Creating Customer Gateways and Vpn connections" -f black -b white
    foreach($e in $endpoints){
      $x=$x+1 ; $error.clear() ; $stack = 0 ; $stackstatus = 0
      $stackname = "$projectname-$site-0$x"
      $vpnconnection ="vpn-$stackname"
      $cgwfile = "./files/customer-gateway-$site.yaml"
      $infile = $yamltemplate
      $outfile = ".\files\$stackname.yaml"
      $endpoint = $e
      $cgw = (Get-CFNExport -region $region | ? Name -like $stackname).Value
      $customergatewayid = ($cgw) ; if($customergatewayid -eq ""){continue}# if cgw is not configured, skip.
      
      #construct tunnel inside /30 ip address # 3rd octet must be between 6 and 168
      $ip=$ip+1
      $tunnelinside01 = "169.254."+$ip+".0/30"
      $tunnelinside02 = "169.254."+$ip+".4/30"

      # construct .yaml cf deployment file.
      Write-Host ""
      Write-Host "Building $outfile file" -f green
      (Get-Content $infile) | Foreach-Object {
          $_ -replace("regexvpntype",$vpntype) `
            -replace("regextgwid",$transitgatewayid) `
            -replace("regexcgw",$stackname) `
            -replace("regexbgpasn",$asn) `
            -replace("regexendpoint",$endpoint) `
            -replace("regexpsk",$presharekey) `
            -replace("regextunnelinside01",$tunnelinside01) `
            -replace("regextunnelinside02",$tunnelinside02) `
            -replace("regexvpnconnection",$vpnconnection)
          } | Set-Content $outfile -force

      Write-host "Validating CF Template" -f yellow -b magenta
      Test-CFNTemplate -templateBody (Get-Content $outfile -raw) -Region $region
      if($error.count -gt 0){Write-Host "Error Validation Failure" ; continue}
      
      try { $stackstatus = ((Get-CFNStack -Stackname $stackname -region $region).StackStatus) }
      
      catch { Write-Host "Stack does not exist!" -f yellow  ; $stack = 1 }
      
      if($stackstatus -eq "CREATE_COMPLETE"){$stack = 0 ; Write-Host "Existing Stack Status: " -f yellow -b magenta -NoNewLine ; Write-Host "CREATE_COMPLETE... Skipping."} 
      if($stackstatus -eq "CREATE_IN_PROGRESS"){Write-Host "Existing Stack Status: " -f yellow -b magenta -NoNewLine ; Write-Host "CREATE_IN_PROGRESS... Skipping."}
      if($stackstatus -ne "CREATE_COMPLETE"){$stack = 2}

      if($stack -eq 2){
          # Stack exists in bad state ->>> Delete it
          Write-Host "Removing Failed Stack"
          Remove-CFNStack -Stackname $stackname -region $region -force  
          Wait-CFNStack -Stackname $stackname -region $region
          } 
      if($stack -ge 1){  
          # Create Stack
          Write-Host "Creating Stack" -f black -b cyan
          New-CFNStack -StackName $stackname -TemplateBody (Get-Content $outfile -raw) -Region $region

          }
      Write-Host ""
      }
    }
    # Cleanup -- Remove failed deployments --- not usefull if failure status reason is needed.
    #if($stackstatus -ne "CREATE_COMPLETE"){
    #  Write-Host "Removing Failed Stack"
    #  Remove-CFNStack -Stackname $stackname -region $region -force  }

Write-Host ""
Write-Host "---------------------------" -f black -b green
Write-Host "Script Processing Complete." -f black -b green
Write-Host "---------------------------" -f black -b green
Write-Host ""