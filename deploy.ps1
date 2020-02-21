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
Write-Host "--------------------------------------" 
Write-Host " Deploying Customer Gateways and VPN. " -f white -b magenta
Write-Host "--------------------------------------"

# Fixed variables
$variables = . "./variables.ps1"
$yamltemplate= "./files/customer-gateway-source.yaml"
$baseip=6 #<-- warning 1-5 is reserved by aws for octect tunnel inside ip 3rd octet
$b=0
#Script Begin
Write-Host "Connecting to account: Master" -f white
Switch-RoleAlias master okta

# Create Customer Gateways
try { $tgwid = (Get-CFNExport -region $region | ? Name -like $tgwstackname).Value}
catch { Write-Host "Transit Gateway stack does not exist, ending script" -f red ; break } #checks if pre-requisite transit gateway cf deployemnt exists and breaks script if not.

#Creates 3rd octet to align with BGP ASN Assignment 
$a=100 #starting 3rd octect for bgp interfaces (will increment based on 3rd and last digit of bgp asn)
$a1= ("$asn").Substring(2,1)
$a2= ("$asn").Substring(4,1)
$concat=$a2+$a1 #concatenates substrings
$a=($a+$concat) #calculates a plus string value of $concat (auto converts to integer)

# Loop through each site to deploy a CGW in
foreach($s in $sites){
  $endpoints = $s.endpoints
  $site = $s.site
  $network = $s.network
  $asn = $s.asn
  $redeploy = $s.redeploy
 
  $x=0 #used for interface numbering.

  #Creates 4th octet
  $b1=$b
  $b2=$b+4
    Write-Host ""
    Write-Host "Processing Customer Gateway:" -f black -b white -NoNewLine ; Write-Host " $projectname-$site " -b Magenta -f white
    foreach($e in $endpoints){
      $x=$x+1
      $stackname = "$projectname-$site-0$x"
      $cgwname = "cgw-$site-0$x"
      $vpnname = "vpn-$site-0$x"
      $vpnconnection ="vpn-$stackname"
      $cgwfile = "./files/customer-gateway-$site.yaml"
      $endpoint = $e

      # Regex query to pull 2nd octet from network and use in addition to base $ip value 3rd octet to enforce ip scheme.
      $regex = "\.(\d)\."
      $network -match $regex > $null
      $ip=$ip+1 ; $ip=$ip+$matches[1]
      
      # Construct tunnel inside /30 ip address # 3rd octet must be between 6 and 168
      $tunnelinside01 = "169.254."+$a+".$b1/30"
      $tunnelinside02 = "169.254."+$a+".$b2/30"
      #increment for next pass
      $b1=$b2+4
      $b2=$b1+4

      #generate password for vpn : not required as it will be automatically generated.
      #$charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".tochararray() 
      #$secret = ($charset | Get-Random -count 20) -join '' 

      # Construct .yaml cf deployment file using regex queries.
      $infile = $yamltemplate
      $outfile = "./files/$stackname.yaml"
      Write-Host "Writing $outfile file" -f green ;
      (Get-Content $infile) | Foreach-Object {
          $_ -replace("regexvpntype",$vpntype) `
             -replace("regextgwid",$tgwid) `
             -replace("regexcgw",$stackname) `
             -replace("regexbgpasn",$asn) `
             -replace("regexendpoint",$endpoint) `
             -replace("regexcgw",$cgwname) `
             -replace("regexvpn",$vpnname) `
             -replace("regextunnelinside01",$tunnelinside01) `
             -replace("regextunnelinside02",$tunnelinside02) `
             -replace("regexvpnconnection",$vpnconnection)
             } | Set-Content $outfile -force     

    $error.clear() ; $stack = 0 ; $stackstatus = 0
    $goodvalues = @("CREATE_COMPLETE","CREATE_IN_PROGRESS")
    try { $stackstatus = ((Get-CFNStack -Stackname $stackname -region $region).StackStatus).Value }
    catch { $stack = 1 ; Write-Host "Stack does not exist..." } # set stack value to 1 if first deployment
    if($redeploy -eq $true){$stack = 2 } #tears down the stack and redeploys if set
      if($rollback -eq $true){$stack = 2 }
    if($stack -eq 0){
        # If stack exists, get the stack deployment status and check against google values
        # If match , set stack value to 0 -> skip iteration, else set stack value to 2.
        
        foreach($v in $goodvalues){if($v -eq $stackstatus){ $stack = 0 ; break } else { $stack = 2 } }}
    if($stack -eq 0){ 
      # Stack already deployed or in process of being deployed -> Skip
      Write-Host "Existing Stack Found - Status: " -f white -b magenta -NoNewLine ; Write-Host " $stackstatus" 
      try{ Wait-CFNStack -Stackname $stackname -region $region } catch {}} # stack deployment already in progress, skip iteration
    if($stack -eq 2){
        # Stack exists in a bad state -> Delete  
        Write-Host "Existing Stack Found - Status: " -f yellow -NoNewLine ; Write-Host " $stackstatus" 
        Write-Host "Removing Stack: " -f white -b red -NoNewLine ; Write-Host " $stackname" -f black -b white
        Remove-CFNStack -Stackname $stackname -region $region -force  
        try{ Wait-CFNStack -Stackname $stackname -region $region } catch {} # try wait for stack removal if needed, catch will hide error if stack does not exist.
        if($rollback -eq $true){ $stack = 0 } #rolling back break loop
        }
    if($stack -ge 1){ # Stack does not exist -> Deploy 
        $error.clear()
        # Attempts to validate the CF template.  
        Write-Host ""
        Write-host "Validating CF Template: " -f Magenta 
        Test-CFNTemplate -templateBody (Get-Content $outfile -raw) -Region $region
        if($error.count -gt 0){Write-Host "Template is NOT valid!" -f red ; Write-Host "" ;  continue } 
        if($error.count -eq 0){Write-Host "Template is valid." -f green ; Write-Host "" }
        Write-Host "Creating Stack: " -f White -b Magenta -NoNewLine ; Write-Host " $stackname"-f black -b white
        New-CFNStack -StackName $stackname -TemplateBody (Get-Content $outfile -raw) -Region $region
        try{ Wait-CFNStack -Stackname $stackname -region $region } catch {}
        }

      }
      $b=$b2+4
    }
    
# Script End
Write-Host ""
Write-Host "---------------------------" 
Write-Host "Script Processing Complete." -f white -b magenta
Write-Host "---------------------------" 
Write-Host ""
Write-Host ""