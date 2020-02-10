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
  ./files/customer-gateway-source.yaml"
  ./variables.ps1
  ./files/cleanup.ps1  
.OUTPUTS
  <./files/<<*multiple*>>.yaml>
.NOTES
  Author: Fraser Elliot Carter Smith
#>

# Script Begin
Write-Host "--------------------------------------" -f black -b green
Write-Host " Deploying Customer Gateways and VPN. " -f black -b green
Write-Host "--------------------------------------" -f black -b green

# Fixed variables
$variables = . "./variables.ps1"
$yamltemplate= "./files/customer-gateway-source.yaml"
$ip=6 #<-- warning 1-5 is reserved by aws for octect tunnel inside ip 3rd octet

# Create Customer Gateways
try { $tgwid = (Get-CFNExport -region $region | ? Name -like $tgwstackname).Value}
catch { Write-Host "Transit Gateway stack does not exist, ending script" -f red ; break } #checks if pre-requisite transit gateway cf deployemnt exists and breaks script if not.

# Loop through each site to deploy a CGW in
foreach($s in $sites){
  $x=0
  $endpoints = $s.endpoints
  $site = $s.site
  $network = $s.network
  $asn = $s.asn
  $redploy = $s.redeploy

    Write-Host ""
    Write-Host "Processing:" -f black -b white -NoNewLine ; Write-Host " $projectname-$site"
    foreach($e in $endpoints){
      $x=$x+1
      $stackname = "$projectname-$site-0$x"
      $vpnconnection ="vpn-$stackname"
      $cgwfile = "./files/customer-gateway-$site.yaml"
      $infile = $yamltemplate
      $outfile = ".\files\$stackname.yaml"
      $endpoint = $e

      # Cleanup 
      if($cleanupmode -eq $true){ $cleanupscript = . "./files/cleanup.ps1" ; $cleanupscript ; Remove-Item $outfile -ErrorAction SilentlyContinue -force ; continue }

      # Regex query to pull 2nd octet from network and use in addition to base $ip value 3rd octet to enforce ip scheme.
      $regex = "\.(\d)\."
      $network -match $regex > $null
      $ip=$ip+1 ; $ip=$ip+$matches[1]
      # Construct tunnel inside /30 ip address # 3rd octet must be between 6 and 168
      $tunnelinside01 = "169.254."+$ip+".0/30"
      $tunnelinside02 = "169.254."+$ip+".4/30"

      #generate password for vpn
      $charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".tochararray() 
      $secret = ($charset | Get-Random -count 20) -join '' 

      # Construct .yaml cf deployment file using regex queries.
      Write-Host "Writing $outfile file" -f green ;
      (Get-Content $infile) | Foreach-Object {
          $_ -replace("regexvpntype",$vpntype) `
            -replace("regextgwid",$tgwid) `
            -replace("regexcgw",$stackname) `
            -replace("regexbgpasn",$asn) `
            -replace("regexendpoint",$endpoint) `
            -replace("regexsecret",$secret) `
            -replace("regextunnelinside01",$tunnelinside01) `
            -replace("regextunnelinside02",$tunnelinside02) `
            -replace("regexvpnconnection",$vpnconnection)
          } | Set-Content $outfile -force     

      $error.clear() ; $stack = 0 ; $stackstatus = 0
      try { $stackstatus = ((Get-CFNStack -Stackname $stackname -region $region).StackStatus).Value }
      catch { $stack = 1 ; Write-Host "Stack does not exist..." -f yellow } # set stack value to 1 if first deployment
      if($redeploy -eq $true){$stack = 2} #tears down the stack and redeploys if set
      if($stack -eq 0){
          # If stack exists, get the stack deployment status and check against google values
          # If match , set stack value to 0 -> skip iteration, else set stack value to 2.
          $goodvalues = @("CREATE_COMPLETE","CREATE_IN_PROGRESS")
          foreach($v in $goodvalues){if($v -eq $stackstatus){ $stack = 0 ; break } else { $stack = 2 } }}
      if($stack -eq 0){ 
          # Stack already deployed or in process of being deployed
          Write-Host "Existing Stack Status:" -f cyan -NoNewLine ; 
          Write-Host " $stackstatus... Skipping." ; continue } # stack deployment already in progress, skip iteration
      if($stack -eq 2){
          # Stack exists in bad state ->>> Delete it 
          Write-Host "Removing Failed Stack..." -f cyan
          Remove-CFNStack -Stackname $stackname -region $region -force  
          try{ Wait-CFNStack -Stackname $stackname -region $region } catch {}# try wait for stack removal if needed, catch will hide error if stack does not exist.
          } 
      if($stack -ge 1){ # Create Stack if $stack = 1 or more
          $error.clear()
          Write-host "Validating CF Template" -f cyan
          Test-CFNTemplate -templateBody (Get-Content $outfile -raw) -Region $region
          if($error.count -gt 0){Write-Host "Error Validation Failure!" -f red ; Write-Host "" ;  continue } # attempts to validate the CF template.
          if($error.count -eq 0){Write-Host "Template is Valid" -f green ; Write-Host "" } 
          Write-Host "Creating Stack" -f black -b cyan
          New-CFNStack -StackName $stackname -TemplateBody (Get-Content $outfile -raw) -Region $region
          }
      Write-Host ""
      }
  }


# Script End
Write-Host ""
Write-Host "---------------------------" -f black -b green
Write-Host "Script Processing Complete." -f black -b green
Write-Host "---------------------------" -f black -b green