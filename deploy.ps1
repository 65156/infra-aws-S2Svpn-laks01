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
  <Modules: PS-AWS-SSO-AUTH
 # Files
  ./files/attachment-source.yaml
  ./files/transit-gateway.yaml>
.OUTPUTS
  <./files/attachment.yaml>
.NOTES
  Author: Fraser Elliot Carter Smith
#>

#configurable variables
$projectname = "cgw"
$uuid = 'laks01'
$region = "ap-southeast-2"
$vpntype = 'ipsec.1'
$transitgatewaystackname = "transit-gateway" #used to reference the transit gateway cf stackname 

#fixed variables
$vpnconnectionsource = "./files/vpn-connection-source.yaml"
$cgwsource = "./files/customer-gateway-source.yaml"

Write-Host "Preparing Files"
$sites = @( 
    [PSCustomObject]@{site="SYD"; network="10.0.0.0/16"; asn="65000"; cgw = ""; endpoints=@("49.255.71.2","14.202.31.162")},
    [PSCustomObject]@{site="LON"; network="10.2.0.0/16"; asn="65002"; cgw = ""; endpoints=@("80.169.133.98","167.98.115.234")},
    [PSCustomObject]@{site="SFO"; network="10.4.0.0/16"; asn="65004"; cgw = ""; endpoints=@("4.14.110.226","12.205.169.10")},
    [PSCustomObject]@{site="TOR"; network="10.6.0.0/16"; asn="65006"; cgw = ""; endpoints=@("172.110.66.2")},
    [PSCustomObject]@{site="HKG"; network="10.8.0.0/16"; asn="65008"; cgw = ""; endpoints=@("203.198.186.225","118.143.126.211")}
) 
Write-Host ""
Write-Host "--------------------------------------" -f black -b green
Write-Host " Deploying Customer Gateways and VPN." -f black -b green
Write-Host "--------------------------------------" -f black -b green
Write-Host ""
Write-Host ""

#Create Customer Gateways
try { $transitgatewayid = (Get-CFNExport -region $region | ? Name -like $transitgatewaystackname).Value ; Write-Host "Transit Gateway Id:" -f black -b cyan -nonewline ; Write-Host " $transitgatewayid" }
catch { Write-Host "Transit Gateway stack does not exist, ending script" -f red ; break } #transit gateway does not exist, script will not process.
foreach($s in $sites){
  
  $endpoints = $s.endpoint
  $site = $s.site
  $network = $s.network
  $asn = $s.asn
  $cgw = $s.cgw
  $cgwfile = "./files/customer-gateway-$site.yaml"
  $infile = $cgwsource
  $outfile = $cgwfile
  $stackname = "$projectname-$site"

  Write-Host "Creating Customer Gateway:" -f black -b white -NoNewLine : Write-Host " $stackname"

    # Find and replace
    Write-Host "Building $infile file" -f green
    (Get-Content $infile) | Foreach-Object {
        $_ -replace("regexbgpasn",$asn) `
          -replace("regexendpoint",$endpoint) `
        } | Set-Content $outfile -force

    $error.clear() ; $stack = 0 ; $stackstatus = 0
    try { $stackstatus = ((Get-CFNStack -Stackname $stackname -region $region).StackStatus) }
    catch { Write-Host "Stack does not exist" -f green  ; $stack = 1 }
    
    if($stackstatus -eq "CREATE_COMPLETE"){$stack = 0 ; Write-Host "Existing Stack Status: " -f yellow -b magenta -NoNewLine ; Write-Host "CREATE_COMPLETE... Skipping."} 
    if($stackstatus -ne "CREATE_COMPLETE"){$stack = 2}

    if($stack -eq 2){
        # Stack exists in bad state ->>> Delete it
        Write-Host "Removing Failed Stack"
        Remove-CFNStack -Stackname $stackname -region $region -force  
        Wait-CFNStack -Stackname $stackname -region $region -Status 'DELETE_COMPLETE' 
        } 
    if($stack -ge 1){  
        # Create Stack
        Write-Host "Creating Stack" -f black -b cyan
        New-CFNStack -StackName $stackname -TemplateBody (Get-Content $outfile -raw) -Region $region
        # Wait for Stack Deployment
        Wait-CFNStack -Stackname $stackname -region $region
        }
    Write-Host ""
    
    Write-Host "Creating Endpoints" -f black -b white
    $stackname = ""
    foreach($e in $endpoints){
      $x=$x+1
      $stackname = "$projectname-connection-0$x"
      $infile = $vpnconnectionsource
      $outfile = ".\files\$stackname.yaml"
      $endpoint = $e
      $customergatewayid = ($s.cgw) ; if($customergatewayid -eq ""){continue}# if cgw is not configured, skip.
      # Find and replace
      Write-Host "Building $infile file" -f green
      (Get-Content $infile) | Foreach-Object {
          $_ -replace("regexvpntype",$vpntype) `
            -replace("regextgwid",$transitgatewayid) `
            -replace("regexcgw",$cgw) `
          } | Set-Content $outfile -force

      $error.clear() ; $stack = 0 ; $stackstatus = 0
      try { $stackstatus = ((Get-CFNStack -Stackname $stackname -region $region).StackStatus) }
      
      catch { Write-Host "Stack does not exist" -f green  ; $stack = 1 }
      
      if($stackstatus -eq "CREATE_COMPLETE"){$stack = 0 ; Write-Host "Existing Stack Status: " -f yellow -b magenta -NoNewLine ; Write-Host "CREATE_COMPLETE... Skipping."} 
      
      if($stackstatus -ne "CREATE_COMPLETE"){$stack = 2}

      if($stack -eq 2){
          # Stack exists in bad state ->>> Delete it
          Write-Host "Removing Failed Stack"
          Remove-CFNStack -Stackname $stackname -region $region -force  
          Wait-CFNStack -Stackname $stackname -region $region -Status 'DELETE_COMPLETE' 
          } 
      if($stack -ge 1){  
          # Create Stack
          Write-Host "Creating Stack" -f black -b cyan
          New-CFNStack -StackName $stackname -TemplateBody (Get-Content $file -raw) -Region $region
          # Wait for Stack Deployment
          Wait-CFNStack -Stackname $stackname -region $region
          }
      Write-Host ""
      }
    }

Write-Host ""
Write-Host "---------------------------" -f black -b green
Write-Host "Script Processing Complete." -f black -b green
Write-Host "---------------------------" -f black -b green
Write-Host ""