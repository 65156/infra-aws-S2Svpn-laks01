#configurable variables
$projectname = "cgw" #<--- becomes the prefix for all cgw stack names and vpn connection stacknames 
$uuid = 'laks01'
$region = "ap-southeast-2"
$vpntype = 'ipsec.1'
$presharekey = "testpassword000001x"
$tgwstackname = "transit-gateway" # must reference the stackname of the transit gateway cf stack for export referencing!
