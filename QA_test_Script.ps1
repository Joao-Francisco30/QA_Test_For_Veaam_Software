#Creates a variable with the Path for the source folder
#$sourcePath = 'C:\QA_test\source'
#Creates a variable with the Path for the replica folder
#$replicaPath = 'C:\QA_test\replica'

param(
    [string]$sourcePath,
    [string]$replicaPath,
    [string]$logFilePath
)

#Variable with the value 0 to later us in case a folder is empty
$isEmpty = 0

#function to create or remove in the replica folder what is in the source folder
function Difer {

    #parameters the function receives when it's being called
    param (
        [string]$srcPath,
        [string]$repPath,
        [string]$lfPath
    )

    #Creates a variable with the children of the source folder
    $sourceFiles  = Get-ChildItem -Path $srcPath -Recurse
    #Creates a variable with the children of the replica folder
    $replicaFiles = Get-ChildItem -Path $repPath -Recurse

    #discover if the source folder is empty
    if ($sourceFiles -eq $null) {
        #if it's null, remove everything from replica
        Get-ChildItem -Path $repPath | Remove-Item -Recurse
        Add-Content -Path $lfPath -Value "Removed all Itens from Replica"
        
        #exit difer function as both folder are empty
        return 1
    }
    
    #Lists the children of the source and replica folders
    Write-Host "source: $($sourceFiles) "
    Write-Host "replica: $($replicaFiles)"

    #discover if the replica folder is empty
    if ($replicaFiles -eq $null) {
        #if yes, for each object on the source folder
        $sourceFiles | foreach {
            
            #Creates the Path for the object
            $relativePath = $_.FullName.Substring($srcPath.Length + 1)
            $itemDestination = Join-Path $repPath $relativePath

            #discover if the object is a container
            if ($_.PSIsContainer) {
                #if yes, create the container on the destination
                New-Item -ItemType Directory -Path $itemDestination -Force
                Add-Content -Path $lfPath -Value "Added the folder $($itemDestination)"
            } else {
                #if not, create the object
                $item = @{
                    'Path'        = $_.FullName
                    'Destination' = $itemDestination
                }
                #command to create the object
                Copy-Item @item -ErrorAction SilentlyContinue 
                Add-Content -Path $lfPath -Value "Added the object $($item.path)"
            }
        }
        #exit difer function as there is no need to check for the diferences between the source and the replica
        #$isEmp = 1
        return 1
    }

    #only do this part when both source and replica folders are NOT EMPTY
    #discover what object are diferent
    $Differences = Compare-Object -ReferenceObject $sourceFiles -DifferenceObject $replicaFiles  

    #Write the differences
    Write-Host "Differences: $($Differences)"

    #for each different object
    $Differences | foreach {
        #set item's Path the name of the object
        $item = @{
            'Path' = $_.InputObject.FullName
        }

        #see if the object exists in source but doesn't in replica
        if ($_.SideIndicator -eq '<=') {
            #create the object path for the replica folder
            $relativePath = $_.InputObject.FullName.Substring($srcPath.Length + 1)
            $item.Destination = Join-Path $repPath $relativePath

            #discover if it's a Directory
            if ($_ -is [System.IO.DirectoryInfo]) {
                #if yes, create the direcotry
                New-Item -ItemType Directory -Path $item.Destination -Force
                Add-Content -Path $lfPath -Value "Added the folder $($item.Destination)"
            } else {
                #if not, create the object
                Copy-Item @item -ErrorAction SilentlyContinue 
                Add-Content -Path $lfPath -Value "Added the Object $($item.Path)"
            }
        }

        #see if the object exists in replica but doesn't in source
        if ($_.SideIndicator -eq '=>') {
        #if yes, remove the item
            $item.Destination = $repPath
            Remove-Item -Path $item.Path -Force
            Add-Content -Path $lfPath -Value "Removed the Object $($item.Path)"
        }
    }
    return 0
}

#function to resolve objects with the same name
function Equ {

    #parameters the function receives when it's called
    param (
        [string]$srcPath,
        [string]$repPath,
        [string]$isEmp,
        [string]$lfPath
    )

    #Write-Host "Empty $($isEmpty)"

    #check is the variable isEmp is 1
    if ($isEmp -eq 1) {
        #if yes, it means that source folder is empty or the replica folder was empty, meaning there is no need to do this function
        Write-Output "Source folder is empty or Replica folder was empty. Skipping Equ function."
        return
    }

    #declare 2 variables to get the children of the source and replica folders
    $sourceFiles = Get-ChildItem -Path $srcPath -Recurse
    $replicaFiles = Get-ChildItem -Path $repPath -Recurse

    #compare the 2 previuos variables to discover equal objects
    $Equals = Compare-Object -ReferenceObject $sourceFiles -IncludeEqual $replicaFiles

    Write-Output $Equals

    #for each equal object
    $Equals | foreach {
        
        #get the path for the object in the replica folder
        $relativePath = $_.InputObject.FullName.Substring($srcPath.Length + 1)
        $destinationPath = Join-Path $repPath $relativePath

        #variable that contains the name and the destination of the object
        $Changeitem = @{
            'Path'        = $_.InputObject.FullName
            'Destination' = $destinationPath
        }

        #discover if the object is a folder
        if ((Get-Item $Changeitem.Path).PSIsContainer) {
            #if yes, write a message
            Write-Output "Skipping directory: $($Changeitem.Path)"
        } else {
            #if not, get the object's content from the source and replica folder
            $sourceContent = Get-Content $Changeitem.Path -Raw
            $replicaContent = Get-Content $Changeitem.Destination -Raw

            #see if one of the objects is null/empty
            if ($sourceContent -and $replicaContent) {
                #compare the objects
                $contentComparison = Compare-Object (Get-Content $Changeitem.Path) (Get-Content $Changeitem.Destination)
                #$contentComparison = Compare-Object $sourceContent $replicaContent
                #discover if there are differences between the content
                if ($contentComparison.Count -eq 0) {
                    #if they are equal, show a message
                    Write-Output "Contents of $($Changeitem.Path) and $($Changeitem.Destination) are identical."
                    #Write-output "source Content $($sourceContent) || replica Content $($replicaContent)"
                } else {
                    #if they aren't equal, show a message and change the content of the object in the replica folder to match the object in the source
                    Write-Output "Contents of $($Changeitem.Path) and $($Changeitem.Destination) are different."
                    #Write-output "source Content $($sourceContent) || replica Content $($replicaContent)"
                    Set-Content -Path $Changeitem.Destination -Value $sourceContent
                    Add-Content -Path $lfPath -Value "Changed the Object $($Changeitem.Destination)"
                }
            } else {
                #if one of the objects is empty, show a message and change the content of the object in the replica folder to match the object in the source
                Write-Output "One or both files have empty content: $($Changeitem.Path), $($Changeitem.Destination)"
                Set-Content -Path $Changeitem.Destination -Value $sourceContent
                Add-Content -Path $lfPath -Value "Changed the Object $($Changeitem.Destination)"
            }
        }
        #add a empty line to help debugging
        Write-Output " "
    }
}

#call the functions
#Write-Output "Empty $($isEmpty)"
Write-Output "Beginning script..."
Write-Output "Beginning script..." | Out-File -Append $logFilePath
$isEmpty = Difer -srcPath $sourcePath -repPath $replicaPath  -lfPath $logFilePath #-isEmp $isEmpty 
Equ -srcPath $sourcePath -repPath $replicaPath -isEmp $isEmpty -lfPath $logFilePath
Write-Output "Script ended" | Out-File -Append $logFilePath
Write-Output "Script ended"