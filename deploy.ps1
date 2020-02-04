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
$projectname = "cgw-and-vpns"
$uuid = 'laks01'
$region = "ap-southeast-2"
$vpntype = 'ipsec.1'
$transitgatewaystackname = "transit-gateway" #used to reference cloudFormation exports

#fixed variables
$vpnconnectionsource = "./files/vpn-connection-source.yaml"
$vpnconnection = "./files/vpn-connection.yaml"

Write-Host "Preparing Files"
$sites = @( 
    #accounts are dependant on account names configured in PS-AWS-SSO-AUTH.psm1
    [PSCustomObject]@{site="Sydney"; network="10.0.0.0/16"; asn="65000" ; endpoint01="49.255.71.2"; cgw=""; endpoint02="14.202.31.162"; $skip = ""},
    [PSCustomObject]@{site="London"; network="10.2.0.0/16"; asn="65002" ; endpoint01="80.169.133.98"; ecgw=""; endpoint02="167.98.115.234"; $skip = ""},
    [PSCustomObject]@{site="SanFrancisco"; network="10.4.0.0/16"; asn="65004" ; endpoint01="4.14.110.226"; cgw=""; endpoint02="12.205.169.10"; $skip = ""},
    [PSCustomObject]@{site="Toronto"; network="10.6.0.0/16"; asn="65006" ; endpoint01="172.110.66.2"; cgw=""; endpoint02=""; $skip = ""},
    [PSCustomObject]@{site="HongKong"; network="10.8.0.0/16"; asn="65008" ; endpoint01="203.198.186.225"; cgw=""; endpoint02="118.143.126.211"; $skip = ""}
) 

Write-Host ""
Write-Host "--------------------------------------" -f black -b green
Write-Host " Deploying Customer Gateways and VPN." -f black -b green
Write-Host "--------------------------------------" -f black -b green
Write-Host ""

Write-Host ""
Write-Host "Create Customer Gateways" -f black -b red



Write-Host ""
Write-Host "Create VPN Connection" -f black -b red
#Create Customer Gateways
$file = $attachment ; $x = 0

try { $transitgatewayid = (Get-CFNExport -region $region | ? Name -like $transitgatewaystackname).Value ; Write-Host "Transit Gateway Id:" -f black -b cyan -nonewline ; Write-Host "$transitgatewayid" }
catch { Write-Host "Stack does not exist" -f green  ; $stack = 1 }
foreach($s in $sites){
    
    $x=$x+1
    $site = $s.site
    $network = $s.network
    $file = $vpnconnectionsource
    $stackname = "$projectname-connection-0$x"
    $skipcheck = ($s.skip) ; if($skipcheck -eq $true){continue} #if marked skip, skip .
    $customergatewayid = ($s.cgw) ; if($customergatewayid -eq ""){continue}# if cgw is not configured, skip.
    # Find and replace
    Write-Host "Building $file file" -f green
    (Get-Content $vpnconnectionsource) | Foreach-Object {
        $_ -replace("regexvpntype",$vpntype) `
           -replace("regextgwid",$transitgatewayid) `
           -replace("regexcgwid",$customergatewayid) `
        } | Set-Content $file -force

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

Write-Host ""
Write-Host "---------------------------" -f black -b green
Write-Host "Script Processing Complete." -f black -b green
Write-Host "---------------------------" -f black -b green
Write-Host ""