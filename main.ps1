#region Classes

class ScriptCheck{
    $ScriptPath
    $Name
    $Type
}

#endregion

#region Notion data model functions
function New-NotionDbSchema{
    param(
        [ValidateSet("Text","Number","Title","Checkbox")]
        $Type
    )
    switch ($Type) {
        "Text" { 
            @{ "rich_text" = @{} }
        }
        "Number"{
            @{ "number" = @{} }
        }
        "Title"{
            @{ "title" = @{} }
        }
        "Checkbox"{
            @{ "checkbox" = @{} }
        }
        Default {
            throw "Unrecognized type: '$Type'"
        }
    }
}

function New-NotionDbProperty{
    param(
        [String]
        [ValidateSet("Text","Number","Title","Checkbox")]
        $Type,
        $Value
    )

    switch ($Type) {
        "Text" { 
            @{
                "rich_text"= @(
                    @{
                        "text"= @{
                            "content"="$Value"
                        }
                    }
                )
            }
        }
        "Number"{
            @{
                "number" = $Value
            }
        }
        "Title"{
            @{   
                "title" = @(
                    @{
                        "text" = @{
                            "content" = "$Value"
                        }
                    }
                )
            }
        }
        "Checkbox"{
            @{
                "checkbox" = $Value
            }
        }
        Default {
            throw "Unrecognized type: '$Type'"
        }
    }
}

#endregion

#region Notion API functions
function Invoke-NotionApiRequest{
    param(
        [String]$Version,
        [String]$Endpoint,
        $Body,
        [String]$Secret,
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method
    )

    Write-Debug "Sending $Method request to $Endpoint"
    $BodyJson = ($Body | ConvertTo-Json -Depth 100)
    if($BodyJson -ne $null){
        Write-Debug -Message $BodyJson
    }else{
        Write-Debug -Message "`$Body is null."
    }
    
    Invoke-RestMethod -Headers @{"Authorization" = $secret; "Notion-Version" = $Version; "Content-Type" = "application/json"} -UseBasicParsing -Method $Method -Uri $Endpoint -Body $BodyJson
}

function Update-NotionDbSchema{
    param(
        [String]$secret,
        [String]$db,
        [PSCustomObject]$Schema
    )

    $Body = @{
        "properties" = $Schema
    }

    Invoke-NotionApiRequest -Version "2022-02-22" -Endpoint "https://api.notion.com/v1/databases/$db" -Secret $secret -Method Patch -Body $Body
}

function New-NotionDbPage{
    param(
        [String] $secret,
        [String] $db,
        [PSCustomObject]$Properties = @{}
    )

    $Body = @{
        "parent" = @{
            "database_id" = "$db"
        }
        "properties" = $Properties
    }

    Invoke-NotionApiRequest -Secret $secret -Version "2022-02-22" -Endpoint "https://api.notion.com/v1/pages" -Method Post -Body $Body
}

function Update-NotionDbPage{
    param(
        [String] $secret,
        [String] $page,
        [PSCustomObject]$Properties = @{}
    )

    $Body = @{
        "properties" = $Properties
    }

    Invoke-NotionApiRequest -Secret $secret -Version "2022-02-22" -Endpoint "https://api.notion.com/v1/pages/$page" -Method Patch -Body $Body
}

function Remove-NotionDbPage{
    param(
        [String] $secret,
        [String] $page
    )

    $Body = @{
        "archived"=$true
    }

    Invoke-NotionApiRequest -Secret $secret -Version "2022-02-22" -Endpoint "https://api.notion.com/v1/pages/$page" -Method Patch -Body $Body
}

function Get-NotionDbPage{
    param(
        [String] $secret,
        [String] $Id
    )
    
    Invoke-NotionApiRequest -Version "2022-02-22" -Endpoint "https://api.notion.com/v1/pages/$Id" -Secret $secret -Method Get
    
}

function Get-NotionDb{
    param(
        [String] $secret,
        [String] $db
    )

    Invoke-NotionApiRequest -Version "2022-02-22" -Endpoint "https://api.notion.com/v1/databases/$db" -Secret $secret -Method Get
}

function Get-NotionDbChildPages{
    param(
        [String] $secret,
        [String] $db
    )
    $Body = @{}
    do{
        $NotionResponse = Invoke-NotionApiRequest -Secret $secret -Version "2022-02-22" -Method Post -Endpoint "https://api.notion.com/v1/databases/$db/query" -Body $Body
        $NotionResults += $NotionResponse.results
        $Body.start_cursor = $NotionResponse.next_cursor
    }while($NotionResponse.has_more)
    $NotionResults
}

#endregion

#region Business functions

function Register-NotionDirectoryLink {
    param(
        [System.IO.DirectoryInfo[]]$Directory,
        [String]$NotionIdFilePath = '/id.notion'
    )

    Write-Host -ForegroundColor Green $Directory.Name

    $CurrentNotionIdFile="$($_.FullName)$($NotionIdFilePath)"
    $CurrentNotionId = $null

    if(Test-Path $CurrentNotionIdFile){
        $CurrentNotionId = Get-Content -Path $CurrentNotionIdFile
        try{
            $ExistingPage = Get-NotionDbPage -secret $secret -Id $CurrentNotionId
            if($ExistingPage.archived){
                $CurrentNotionId = $null
                Write-Host "A linked notion page already exists, but it is archived."
            }else{
                Write-Host "A linked notion page already exists."
            }
        }catch{
            $CurrentNotionId = $null
            Remove-Item $CurrentNotionIdFile
            Write-Host  "A linked notion page could not be located. ($($_.Exception.Message))"
        }
    }
    
    if(-Not $CurrentNotionId){
        [PSCustomObject]$NewProperties = @{}
        $NewProperties.Name = (New-NotionDbProperty -Type Title -Value $Directory.Name )
        $NotionResponse = New-NotionDbPage -secret $secret -db $db -properties $NewProperties
        Write-Debug -Message $NotionResponse
        $CurrentNotionId = $NotionResponse.id
        Write-Host "A new linked notion page has been created: $CurrentNotionId"
        $CurrentNotionId | Out-File -FilePath $CurrentNotionIdFile
    }

    Write-Output $CurrentNotionId

}
#endregion

$db = "b103cdddd45d43dda84e8cff956d137e"
$secret = Get-Content "$PSScriptRoot/token.secret"
$ChecksFolder = "$PSScriptRoot/checks"
$TargetFolder = "T:\WIP"
$Filter = '*'
$NotionPropertyNamePrefix = "."

#region Initialize

$TargetDirectories = Get-ChildItem -Directory -Path $TargetFolder -Filter $Filter

[ScriptCheck[]]$Checks = @()
Get-ChildItem -Path $ChecksFolder -File -Filter '*.ps1' | ForEach-Object{
    $Checks += [ScriptCheck]@{
        "ScriptPath"=$_.FullName;
        "Name"=$_.BaseName.split('-')[1];
        "Type" = $_.BaseName.split('-')[0]
    }
}
$LongestCheckNameLength = ($Checks.Name | Measure-Object -Maximum -Property Length).Maximum

# Write checks and directories
Write-Host -ForegroundColor Yellow "Loaded Directories"
$TargetDirectories

Write-Host -ForegroundColor Yellow "Loaded Checks"
$Checks
#endregion

#region Calculate new Notion DB schema
$NewDbSchema = @{}

$Checks | ForEach-Object{
    $NewPropertySchema = New-NotionDbSchema -Type $_.Type
    $NewDbSchema[".$($_.Name)"] = $NewPropertySchema
}

# Get Old Notion DB schema

$OldDbSchema = @{}

$NotionDb = Get-NotionDb -secret $secret -db $db
$NotionDb.properties | Get-Member | Where-Object{$_.Name -like "$NotionPropertyNamePrefix*"} | ForEach-Object{
    $OldDbSchema.Add($_.Name,$null)
}

# Replace new schema into old schema

$UpdateSchema = $OldDbSchema

$NewDbSchema.Keys | ForEach-Object{
    $UpdateSchema[$_] = $NewDbSchema[$_]
}

Update-NotionDbSchema -secret $secret -db $db -Schema $UpdateSchema

#endregion

#region Perform Sync
$NotionPageIds = @()

$TargetDirectories | ForEach-Object{
    $CurrentDirectory = $_
    $CurrentNotionId = (Register-NotionDirectoryLink -Directory $_)
    $NotionPageIds += $CurrentNotionId

    $NewProperties = @{}

    $Checks | ForEach-Object{
        $CurrentCheck = $_
        Write-Debug -Message ($CurrentCheck | ConvertTo-Json -Depth 100)
        try{
            $Result = (& $CurrentCheck.ScriptPath $CurrentDirectory.FullName | Select-Object -Last 1)
        }catch{
            Write-Warning "'$($CurrentCheck.ScriptPath)' for directory '$CurrentDirectory' could not be processed: $_"
            $Result = $false
        }
        Write-Host -ForegroundColor Cyan "$($CurrentCheck.Name.PadRight($LongestCheckNameLength+3,' ')): $Result"
        $NewProperties["$NotionPropertyNamePrefix$($CurrentCheck.Name)"] = (New-NotionDbProperty -Type $_.Type -Value $Result)
        
    }
    Write-Debug ($NewProperties | ConvertTo-Json -Depth 100)
    $NotionResponse = Update-NotionDbPage -secret $secret -page $CurrentNotionId -properties $NewProperties
    Write-Debug -Message ($NotionResponse | ConvertTo-Json -Depth 100)
}
#endregion

#region Delete Orphaned Notion Pages

$RemotePages = Get-NotionDbChildPages -secret $secret -db $db

$PagesToDelete = $RemotePages | Where-Object {$_.id -notin $NotionPageIds}
Write-Host "$(($PagesToDelete|Measure-Object).Count) pages are no longer referenced by a directory and will be deleted."

$PagesToDelete | ForEach-Object{
    $NotionResponse = Remove-NotionDbPage -secret $secret -page $_.id
    Write-Debug -Message ($NotionResponse | ConvertTo-Json -Depth 100)
}
#endregion