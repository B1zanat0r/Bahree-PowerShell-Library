<#
.SYNOPSIS 
    Asynchronously start all or specific Azure VMs in an Azure Subscription

.DESCRIPTION
    This script asynchronously starts either all Azure VMs in an Azure Subscription, or all Azure VMs in one or more specified Resource Groups, or a specific Azure VM. The choice around which VMs to start
    depends on the parameters provided. This script has a dependency on the "Get-AzureRMVMPowerState.ps1" script, which it calls to check each VMs Power State before tryign to start it.

.PARAMETER ResourceGroupName
    Name of the Resource Group containing the VMs you want to remote Into. Specifying just the Resource Group without the $VMName parameter, will consider all VMs in this specified Resource Group

.PARAMETER VMName    
    Name of the VM you want to remote Into. this parameter cannot be specified without it's Resource group in the $ResourceGroupName parameter, or else will throw error  

.EXAMPLE
    Start-AzureRMVMAll.ps1
    Start-AzureRMVMAll.ps1 -ResourceGroupName "RG1"
    Start-AzureRMVMAll.ps1 -ResourceGroupName "RG1,RG2,RG3"
    Start-AzureRMVMAll.ps1 -ResourceGroupName "RG1" -VMName "VM01"
    
.Notes
    Author: Arjun Bahree
    E-mail: arjun.bahree@gmail.com
    Creation Date: 6/Dec/2017
    Last Revision Date: 15/Dec/2017
    Version: 3.0
    Development Environment: Azure Automation Runbook Editor and VS Code IDE
    PS Version: 5.1
    Platform: Windows
#>

[CmdletBinding()]
param(
 
    [Parameter(Mandatory=$false)]
    [String[]]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [String]$VMName
)

if (!(Get-AzureRmContext).Account){
    Write-Error "You need to be logged into your Azure Subscription using PowerShell cmdlet 'Login-AzureRmAccount'"
    return
}  

[System.Collections.ArrayList]$jobQ = @()

# Check if both Resource Groups and VM Name params are not passed
If (!$PSBoundParameters.ContainsKey('ResourceGroupName') -And !$PSBoundParameters.ContainsKey('VMName'))
{
    # Get a list of all the Resource Groups in the Azure Subscription
    $RGs = Get-AzureRmResourceGroup 
    
    # Check if there are Resource Groups in the current Azure Subscription
    if ($RGs)
    {        
        # Iterate through all the Resource Groups in the Azure Subscription        
        foreach ($rg in $RGs)
        {
            $RGBaseName = $rg.ResourceGroupName
            
            # Get a list of all the VMs in the specific Resource Group for this Iteration
            $VMs = Get-AzureRmVm -ResourceGroupName $RGBaseName

            if ($VMs)
            {
                # Iterate through all the VMs within the specific Resource Group for this Iteration
                foreach ($vm in $VMs)
                {
                    $VMBaseName = $vm.Name

                    $VMState = .\Get-AzureRMVMPowerState.ps1 -ResourceGroupName $RGBaseName -VMName $VMBaseName
                    
                    if ($VMState)
                    {
                        if ($VMState -eq "deallocated" -Or $VMState -eq "stopped")
                        {
                            Write-Verbose "The VM {$VMBaseName} in Resource Group {$RGBaseName} is currently Deallocated/Stopepd. Starting VM..."
                            $retval = Start-AzureRmVM -ResourceGroupName $RGBaseName -Name $VMBaseName -AsJob
                            $jobQ.Add($retval) > $null
                        }
                        elseif($VMState -eq "running" -Or $VMState -eq "starting") {
                            Write-Verbose "The VM {$VMBaseName} in Resource Group {$RGBaseName} is either already Started or Starting."
                            continue
                        }
                        elseif($VMState -eq "stopping" -Or $VMState -eq "deallocating") {
                            Write-Verbose "The VM {$VMBaseName} in Resource Group {$RGBaseName} is in a transient state of Stopping or Deallocating. Hence, cannot start VM in between the process."
                            continue
                        }
                    }
                    else {
                        Write-Verbose "Unable to determine PowerState of the VM {$VMBaseName} in Resource Group {$RGBaseName}. Hence, cannot start the VM. Skipping to next VM..."
                        continue
                    }
                }
            }
            else
            {
                Write-Verbose "There are no VMs in the Resource Group {$RGBaseName}. Continuing with next Resource Group, if any."
                continue
            }
        }
    }
    else
    {
        Write-Error "There are no Resource Groups in the Azure Subscription {$AzureSubscriptionId}. Aborting..."
        return $null
    }
}
# Check if only Resource Group param is passed, but not the VM Name param
Elseif ($PSBoundParameters.ContainsKey('ResourceGroupName') -And !$PSBoundParameters.ContainsKey('VMName'))
{
    foreach ($rg in $ResourceGroupName)
    {
        # Get a list of all the VMs in the specific Resource Group
        $VMs = Get-AzureRmVm -ResourceGroupName $rg
        
        if ($VMs)
        {
        # Iterate through all the VMs within the specific Resource Group for this Iteration
            foreach ($vm in $VMs)
            {
                $VMBaseName = $vm.Name

                $VMState = .\Get-AzureRMVMPowerState.ps1 -ResourceGroupName $rg -VMName $VMBaseName -State "PowerState"
                
                if ($VMState)
                {
                    if ($VMState -eq "deallocated" -Or $VMState -eq "stopped")
                    {
                        Write-Verbose "The VM {$VMBaseName} in Resource Group {$rg} is currently Deallocated/Stopepd. Starting VM..."
                        $retval = Start-AzureRmVM -ResourceGroupName $rg -Name $VMBaseName -AsJob
                        $jobQ.Add($retval) > $null
                    }
                    elseif($VMState -eq "running" -Or $VMState -eq "starting") {
                        Write-Verbose "The VM {$VMBaseName} in Resource Group {$rg} is either already Started or Starting."
                        continue
                    }
                    elseif($VMState -eq "stopping" -Or $VMState -eq "deallocating") {
                        Write-Verbose "The VM {$VMBaseName} in Resource Group {$rg} is in a transient state of Stopping or Deallocating. Hence, cannot start VM in between the process."
                        continue
                    }
                }
                else{
                    Write-Verbose "Unable to determine PowerState of the VM {$VMBaseName} in Resource Group {$rg}. Hence, cannot start the VM. Skipping to next VM..."
                    continue
                }
            }
        }
        else
        {
            Write-Verbose "There are no Virtual Machines in Resource Group {$rg}. Skipping to next Resource Group"
            continue
        }
    }
}
# Check if both Resource Group and VM Name params are passed
Elseif ($PSBoundParameters.ContainsKey('ResourceGroupName') -And $PSBoundParameters.ContainsKey('VMName'))
{

    # Get the specified VM in the specific Resource Group
    $vm = Get-AzureRmVm -ResourceGroupName $ResourceGroupName -Name $VMName

    if ($vm)
    {    
        $VMBaseName = $vm.Name

        $VMState = .\Get-AzureRMVMPowerState.ps1 -ResourceGroupName $ResourceGroupName -VMName $VMBaseName -State "PowerState"
        
        if ($VMState)
        {
            if ($VMState -eq "deallocated" -Or $VMState -eq "stopped")
            {
                Write-Verbose "The VM {$VMBaseName} in Resource Group {$ResourceGroupName} is currently Deallocated/Stopepd. Starting VM..."
                $retval = Start-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VMBaseName -AsJob
                $jobQ.Add($retval) > $null
            }
        }
        else {
            Write-Verbose "Unable to determine PowerState of the VM {$VMBaseName} in Resource Group {$ResourceGroupName}. Hence, cannot start the VM. Skipping to next VM..."
            continue
        }
    }
    else
    {
        Write-Error "There is no Virtual Machine named {$VMName} in Resource Group {$ResourceGroupName}. Aborting..."
        return
    }
}
# Check if Resource Group param is not passed, but VM Name param is passed
Elseif (!$PSBoundParameters.ContainsKey('ResourceGroupName') -And $PSBoundParameters.ContainsKey('VMName'))
{
    Write-Error "VM Name parameter cannot be specified alone, without specifying its Resource Group Name parameter also. Aborting..."
    return
}

$jobStatus = 0

while ($jobStatus -ne $jobQ.Count)
{ 
    foreach ($job in $jobQ)
    {
        if ($job.State -eq "Completed")
        {
            Remove-Job $job.Id
            $jobStatus++
            continue
        }
    }

    if( $jobStatus -eq $jobQ.Count)
    {
        Write-Information "All VMs have been started!"
    }
}