#region Parameters

param(
    [String]
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory=$true)]
    $NotionDatabase,

    [String]
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory=$true)]
    $NotionSecret,

    [System.IO.DirectoryInfo]
    $CheckScriptsDirectory = "$PSScriptRoot/checks",

    [Parameter(Mandatory=$true)]
    [System.IO.DirectoryInfo[]]
    [ValidateScript({ $_ | % { $_.Exists } })]
    $Directory,

    [String]
    $Filter = '*',

    [String]
    $NotionPropertyNamePrefix = ".",

    [String]
    [ValidateNotNullOrEmpty()]
    $NotionIdFilePath = "/id.notion"
)

#endregion

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
        [String]
        [Parameter(Mandatory=$true)]
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
        [Parameter(Mandatory=$true)]
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
        [Parameter(Mandatory=$true)][String]$Version,
        [Parameter(Mandatory=$true)][String]$Endpoint,
        $Body,
        [Parameter(Mandatory=$true)][String]$Secret,
        [Parameter(Mandatory=$true)][Microsoft.PowerShell.Commands.WebRequestMethod]$Method
    )

    Write-Debug "Sending $Method request to $Endpoint"
    if($Body -ne $null){
        $BodyJson = ($Body | ConvertTo-Json -Depth 100)
    }else{
        $BodyJson = $null
    }

    if($BodyJson -ne $Null){
        Write-Debug -Message $BodyJson
    }else{
        Write-Debug -Message "`$Body is null."
    }

    $TryAgain = $false
    do {
        try{
            Invoke-RestMethod -Headers @{"Authorization" = $Secret; "Notion-Version" = $Version; "Content-Type" = "application/json"} -UseBasicParsing -Method $Method -Uri $Endpoint -Body $BodyJson
        }catch{
            if($_.Exception.Response.StatusCode.value__ -eq "429"){
                Write-Warning "Notion is receiving too many requests (429). The script will wait a few seconds."
                $TryAgain = $true
                Start-Sleep -Seconds 3
            }else{
                Write-Error "Notion responded with an error: $($_.Exception.Response.StatusCode.value__) ($($_.Exception.Response.StatusDescription))"
            }
        }
    } while($TryAgain)
    
}
function Update-NotionDbSchema{
    param(
        [Parameter(Mandatory=$true)][String]$Secret,
        [Parameter(Mandatory=$true)][String]$Database,
        [Parameter(Mandatory=$true)][PSCustomObject]$Schema
    )

    $Body = @{
        "properties" = $Schema
    }

    Invoke-NotionApiRequest -Version "2022-02-22" -Endpoint "https://api.notion.com/v1/databases/$Database" -Secret $Secret -Method Patch -Body $Body
}

function New-NotionDbPage{
    param(
        [Parameter(Mandatory=$true)][String] $Secret,
        [Parameter(Mandatory=$true)][String] $Database,
        [PSCustomObject]$Properties = @{}
    )

    $Body = @{
        "parent" = @{
            "database_id" = "$Database"
        }
        "properties" = $Properties
    }

    Invoke-NotionApiRequest -Secret $Secret -Version "2022-02-22" -Endpoint "https://api.notion.com/v1/pages" -Method Post -Body $Body
}

function Update-NotionDbPage{
    param(
        [Parameter(Mandatory=$true)][String] $Secret,
        [Parameter(Mandatory=$true)][String] $Page,
        [PSCustomObject]$Properties = @{}
    )

    $Body = @{
        "properties" = $Properties
    }

    Invoke-NotionApiRequest -Secret $Secret -Version "2022-02-22" -Endpoint "https://api.notion.com/v1/pages/$Page" -Method Patch -Body $Body
}

function Remove-NotionDbPage{
    param(
        [Parameter(Mandatory=$true)][String] $Secret,
        [Parameter(Mandatory=$true)][String] $Page
    )

    $Body = @{
        "archived"=$True
    }

    Invoke-NotionApiRequest -Secret $Secret -Version "2022-02-22" -Endpoint "https://api.notion.com/v1/pages/$Page" -Method Patch -Body $Body
}

function Get-NotionDbPage{
    param(
        [Parameter(Mandatory=$true)][String] $Secret,
        [Parameter(Mandatory=$true)][String] $Page
    )
    
    Invoke-NotionApiRequest -Version "2022-02-22" -Endpoint "https://api.notion.com/v1/pages/$Page" -Secret $Secret -Method Get
    
}

function Get-NotionDb{
    param(
        [Parameter(Mandatory=$true)][String] $Secret,
        [Parameter(Mandatory=$true)][String] $Database
    )

    Invoke-NotionApiRequest -Version "2022-02-22" -Endpoint "https://api.notion.com/v1/databases/$Database" -Secret $Secret -Method Get
}

function Get-NotionDbChildPages{
    param(
        [Parameter(Mandatory=$true)][String] $Secret,
        [Parameter(Mandatory=$true)][String] $Database
    )
    $Body = @{}
    do{
        $NotionResponse = Invoke-NotionApiRequest -Secret $Secret -Version "2022-02-22" -Method Post -Endpoint "https://api.notion.com/v1/databases/$Database/query" -Body $Body
        $NotionResults += $NotionResponse.results
        $Body.start_cursor = $NotionResponse.next_cursor
    }while($NotionResponse.has_more)
    $NotionResults
}

#endregion

#region Business functions

function Register-NotionDirectoryLink {
    param(
        [Parameter(Mandatory=$true)][System.IO.DirectoryInfo]$Directory,
        [Parameter(Mandatory=$true)][String]$NotionIdFilePath
    )

    Write-Host -ForegroundColor Green $Directory.Name
    
    $CurrentNotionIdFile="$($_.FullName)$($NotionIdFilePath)"
    $CurrentNotionId = $Null

    if(Test-Path $CurrentNotionIdFile){
        $CurrentNotionId = Get-Content -Path $CurrentNotionIdFile
        try{
            $ExistingPage = Get-NotionDbPage -Secret $NotionSecret -Page $CurrentNotionId
            if($ExistingPage.archived){
                $CurrentNotionId = $Null
                Write-Host "A linked Notion page already exists, but it is archived. A new one will be created..."
            }else{
                Write-Host "A linked Notion page already exists."
            }
        }catch{
            $CurrentNotionId = $Null
            Remove-Item $CurrentNotionIdFile
            Write-Host  "A linked Notion page could not be located. A new one will be created..."
            Write-Debug $_.Exception.Message
        }
    }
    
    if(-Not $CurrentNotionId){
        [PSCustomObject]$NewProperties = @{}
        $NewProperties.Name = (New-NotionDbProperty -Type Title -Value $Directory.Name )
        $NotionResponse = New-NotionDbPage -Secret $NotionSecret -Database $NotionDatabase -properties $NewProperties
        Write-Debug -Message $NotionResponse
        $CurrentNotionId = $NotionResponse.id
        Write-Host "A new linked Notion page has been created: $CurrentNotionId"
        $CurrentNotionId | Out-File -FilePath $CurrentNotionIdFile
    }

    Write-Output $CurrentNotionId

}
#endregion

#region Initialize

$TargetDirectories = @()
$Directory | ForEach-Object{
    Get-ChildItem -Directory -Path $Directory -Filter $Filter | ForEach-Object{
        $TargetDirectories += $_
    }
}

[ScriptCheck[]]$Checks = @()
if($CheckScriptsDirectory.Exists){
    Get-ChildItem -Path $CheckScriptsDirectory -File -Filter '*.ps1' | ForEach-Object{
        $Checks += [ScriptCheck]@{
            "ScriptPath"=$_.FullName;
            "Name"=$_.BaseName.split('-')[1];
            "Type" = $_.BaseName.split('-')[0]
        }
    }
    $LongestCheckNameLength = ($Checks.Name | Measure-Object -Maximum -Property Length).Maximum
}else{
    Write-Warning "The script directory '$($CheckScriptsDirectory)' could not be opened. No checks will be performed."
}


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

$NotionDb = Get-NotionDb -Secret $NotionSecret -Database $NotionDatabase
$NotionDb.properties | Get-Member | Where-Object{$_.Name -like "$NotionPropertyNamePrefix*"} | ForEach-Object{
    $OldDbSchema.Add($_.Name,$Null)
}

# Replace new schema into old schema

$UpdateSchema = $OldDbSchema

$NewDbSchema.Keys | ForEach-Object{
    $UpdateSchema[$_] = $NewDbSchema[$_]
}

$SchemaUpdateResult = Update-NotionDbSchema -Secret $NotionSecret -Database $NotionDatabase -Schema $UpdateSchema

#endregion

#region Perform Sync
$NotionPageIds = @()

$TargetDirectories | ForEach-Object{
    $CurrentDirectory = $_
    $CurrentNotionId = (Register-NotionDirectoryLink -Directory $_ -NotionIdFilePath $NotionIdFilePath)
    $NotionPageIds += $CurrentNotionId

    $NewProperties = @{}

    $NewProperties.Name = (New-NotionDbProperty -Type Title -Value $CurrentDirectory.Name )

    $Checks | ForEach-Object{
        $CurrentCheck = $_
        Write-Debug -Message ($CurrentCheck | ConvertTo-Json -Depth 100)
        try{
            $OldLocation = Get-Location
            $Result = (& $CurrentCheck.ScriptPath $CurrentDirectory.FullName | Select-Object -Last 1)
            Set-Location $OldLocation
        }catch{
            Write-Warning "'$($CurrentCheck.ScriptPath)' for directory '$CurrentDirectory' could not be processed: $_"
            $Result = $False
        }
        Write-Host -ForegroundColor Cyan "$($CurrentCheck.Name.PadRight($LongestCheckNameLength+3,' ')): $Result"
        $NewProperties["$NotionPropertyNamePrefix$($CurrentCheck.Name)"] = (New-NotionDbProperty -Type $_.Type -Value $Result)
        
    }
    Write-Debug ($NewProperties | ConvertTo-Json -Depth 100)
    $NotionResponse = Update-NotionDbPage -Secret $NotionSecret -page $CurrentNotionId -properties $NewProperties
    Write-Debug -Message ($NotionResponse | ConvertTo-Json -Depth 100)
}
#endregion

#region Delete Orphaned Notion Pages

$RemotePages = Get-NotionDbChildPages -Secret $NotionSecret -Database $NotionDatabase

$PagesToDelete = $RemotePages | Where-Object {$_.id -notin $NotionPageIds}
Write-Host "$(($PagesToDelete|Measure-Object).Count) pages are no longer referenced by a directory and will be deleted..."

$PagesToDelete | ForEach-Object{
    $NotionResponse = Remove-NotionDbPage -Secret $NotionSecret -page $_.id
    Write-Debug -Message ($NotionResponse | ConvertTo-Json -Depth 100)
}
#endregion