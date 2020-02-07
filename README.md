# infra-aws-S2Svpn-laks01
# configurable settings are within variables.ps1
# No changes should be made within deploy.ps1
# ./files directory is used for swap location and contains a cleanup.ps1 script used to delete all deployed stacks (should this be required)
# script logic will redeploy failed stacks, remove stacks stuck in a failed state, redeploy stacks if specifically marked for redployment.