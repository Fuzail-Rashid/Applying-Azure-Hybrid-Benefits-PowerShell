param($mySbMsg, $TriggerMetadata)

Write-Information "PowerShell ServiceBus queue trigger function processed message: $mySbMsg"

Write-Information "value in service bus :" $mySbMsg.resourceUri

$CorelationId =if ($mySbMsg.CorrelationId){
    Write-Information "Value of $mySbMsg.CorrelationId"
} else {New-Guid}
Write-Information "value of corelationid :$CorelationId"
#Handle and process the message, resourceId
$resourceId = if ($mySbMsg.resourceUri) { $mySbMsg.resourceUri }
Write-Information "The following resouriceId was passed: $resourceId"

if ($resourceId) {
    $isVm = if ($resourceId.split('/')[7] -eq "virtualMachines") { $true } else { $false }
    $subscriptionid = $resourceId.split('/')[2]
    Write-Information "value in subscription:$subscriptionid" 
    $ResourceGroupName =  $resourceId.split("/")[4]
    Write-Information "value in ResourceGroupName :$ResourceGroupName"
    $VmName = $resourceId.split("/")[8]
    Write-Information "value in VmName :$VmName"
   
    if ($isVm) {
        Write-Information "IsVm verification passed. Processing VM."

        Write-Information "Connecting to Azure"
        Connect-AzAccount -Identity
        Write-Information "Connected to Azure"
        
        #Get the VM
       
        Write-Information "setting the context"
        Set-AzContext -SubscriptionName  $subscriptionid 
        try {
            $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName -ErrorAction Stop
        
            Write-Host "Printing Vm Name :" $vm.Name
        }
        catch {
            Write-Error "Error fetching the vms from azure backend"
            throw
        }
       
         
        try {
            if ($vm) {
                Write-Host "The value of vm tags is" $vm.tags.HYBRIDBENEFITS
                
                    # Checking for Windows machine           
                    if ($vm.StorageProfile.OsDisk.OsType -eq "Windows") {
                        # Validate whether hybrid benefit is already applied  
                           
                        # Checking for License Type
                        if (!($vm.LicenseType) -or ($vm.LicenseType -eq "None")) {
                            # Assign the machine to use 'Windows_Server' license type
                            try {
                                # This license type applies Azure Hybrid Benefits
                                Write-Information "Applying Hybrid benefit to" $vm.Name
                                $vm.LicenseType = "Windows_Server"
                                # Update the VM configuration
                                Update-AzVM   -ResourceGroupName $ResourceGroupName -VM $vm
                                
                                
                                #################################################################################################################
                                #logging the corelation id in log analyticss
                                #################################################################################################################
                                try {
                                    $logCorelationId = $env:logCorelationIdUriVm
                                    $deregBodyObject = [PSCustomObject]@{CorelationId=$CorelationId
                                                                        resourceId = $resourceId
                                                                        vm =$vm
                                                                        }
                                    $deregBodyJSON = ConvertTo-Json($deregBodyObject)
                                    Write-Host  "Value of body is : $deregBodyJSON"
                                    $deregresponse = Invoke-RestMethod -Uri $logCorelationId -Method POST -Body $deregBodyJSON -ContentType 'application/json' 
                                    Write-Host "Logging of corelation id is successfully done with message :" $deregresponse.Status     
                                }
                                catch {
                                    Write-Error "Issue with Logging api,can proceed..."
                                }

                                #############################################################################################
                                # Calling the email api 
                                ##############################################################################################

                                Write-Host "Calling the email api"
                                try {
                                    $emailtocontacts = $env:EmailApiUriHbVm
                                    $emailBodyObject = [PSCustomObject]@{"resourceId"="$resourceId"}
                                    $emailBodyJSON = ConvertTo-Json($emailBodyObject)
                                    $emailresponse = Invoke-RestMethod -Uri $emailtocontacts -Method POST -Body $emailBodyJSON -ContentType 'application/json' 
                                    Write-Host "Email is successfully done with message :" $emailresponse.Status        
                                }
                                catch {
                                    Write-Error "Issue with Email api,can proceed..."
                                }
                            }
                            catch {
                                Write-Error "Error while applying the Hybrid benefits on a vm: $vm"
                                throw
                            }
                       
                
                        }
                        elseif ($vm.LicenseType -eq "Windows_Server") {
                            Write-Information "Hybrid Benefits are already enabled"
                            
                        }
                   
            
                    }
                }
                
                if ($null -ne $vm.OSProfile.LinuxConfiguration)
                {
                    Write-Host "Hybrid benefit cannot be applied to machine as it is a Linux VM." $vm.Name 
                    
                }
            else {
                Write-Information "The Virtual Machine wasnt passed"
            }
        }
        catch {
            Write-Error "Error while applying the Hybrid benefits on a vm: $resourceId"
            throw
        }
    }
}

#Turning Hybrid benefits off if the exlusion tag is given

if ($vm.tags.HYBRIDBENEFITS -eq "False") {
    Write-Information "Exclude from turning the Hybrid Benefits on" 
    $vm.LicenseType = "None"
    Update-AzVM   -ResourceGroupName $ResourceGroupName -VM $vm
}

