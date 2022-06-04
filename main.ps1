
class NotionProperty : PSCustomObject {}
class NotionPropertyCollection : System.Collections.Generic.Dictionary[System.String,PSCustomObject] {}

class NotionPropertySchema : PSCustomObject {}
class NotionPropertySchemaCollection :  System.Collections.Generic.Dictionary[System.String,PSCustomObject] {}

class ScriptCheck{
    $ScriptPath
    $Name
    $Type
}

class NotionDataModel{
    # Rich Text
    static [NotionPropertySchema] $RichTextSchema = @{
        "rich_text" = @{}
    }
    static [NotionProperty] NewRichTextProperty ([string]$Text){
        return @{
            "rich_text"= @(
                @{
                    "text"= @{
                        "content"="$Text"
                    }
                }
            )
        }
    }

    # Title
    static [NotionPropertySchema] $TitleSchema = @{
        "title" = @{}
    }
    static [NotionProperty] NewTitlePropertyValue ([String]$Title){
        return @{   
            "title" = @(
                @{
                    "text" = @{
                        "content" = "$Title"
                    }
                }
            )
        }
    }

    # Number
    static [NotionPropertySchema] $NumberSchema = @{
        "number" = @{}
    }
    static [NotionProperty] NewNumberProperty ([System.ValueType]$Number){
        return @{
            "number" = $Number
        }
    }

    # Checkbox

    static [NotionPropertySchema] $CheckboxSchema = @{
        "checkbox" = @{}
    }
    static [NotionProperty] NewCheckboxProperty ([Boolean]$Checked){
        return @{
            "checkbox" = $Checked
        }
    }
}

function Invoke-NotionApiRequest{
    param(
        [String]$Version,
        [String]$Endpoint,
        $Body,
        [String]$Secret,
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method
    )

    Write-Host -ForegroundColor Yellow "Sending request to $Endpoint"
    Invoke-RestMethod -Headers @{"Authorization" = $secret; "Notion-Version" = $Version; "Content-Type" = "application/json"} -UseBasicParsing -Method $Method -Uri $Endpoint -Body ($Body | ConvertTo-Json -Depth 100)
}

function Update-NotionDbSchema{
    param(
        [String]$secret,
        [String]$db,
        [NotionPropertySchemaCollection]$Schema
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
        [NotionPropertyCollection]$Properties = @{}
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
        [NotionPropertyCollection]$Properties = @{}
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


$db = "b103cdddd45d43dda84e8cff956d137e"
$secret = Get-Content "$PSScriptRoot/token.secret"
$ChecksFolder = "$PSScriptRoot/checks"
$TargetFolder = "C:\Users\Lennart\ambientCG-Import"

# Load Folder to process and scripts to run

$LocalDirectories = Get-ChildItem -Directory -Path $TargetFolder

[ScriptCheck[]]$Checks = @()
Get-ChildItem -Path $ChecksFolder -File -Filter '*.ps1' | ForEach-Object{
    $Checks += [ScriptCheck]@{
        "ScriptPath"=$_.FullName;
        "Name"=$_.BaseName.split('-')[1];
        "Type" = $_.BaseName.split('-')[0]
    }
}

Write-Host -ForegroundColor Yellow "Loaded Directories"
$LocalDirectories

Write-Host -ForegroundColor Yellow "Loaded Checks"
$Checks

# Update list of notion pages to reflect existing folders

$RemotePages = Get-NotionDbChildPages -secret $secret -db $db

# Create notion pages for new folders

$ValidNotionPageIds = @()
$LocalDirectories | ForEach-Object{
    $CurrentDirectory = $_
    $CurrentNotionIdFile="$($CurrentDirectory.FullName)/id.notion"
    $CurrentNotionId = $null

     Write-Host -ForegroundColor Green $CurrentDirectory

    if(Test-Path $CurrentNotionIdFile){
        Write-Host -ForegroundColor Yellow "Found a Notion ID file."
        $CurrentNotionId = Get-Content -Path $CurrentNotionIdFile
        try{
            $ExistingPage = Get-NotionDbPage -secret $secret -Id $CurrentNotionId
            Write-Host -ForegroundColor Yellow "Referenced Page exists."
            if($ExistingPage.archived){
                $CurrentNotionId = $null
                Write-Host -ForegroundColor Yellow "Referenced Page is archived"
            }
        }catch{
            Write-Host -ForegroundColor Yellow "Referenced Page not found. Reseting..."
            $CurrentNotionId = $null
            Remove-Item $CurrentNotionIdFile
        }
    }

    [NotionPropertyCollection]$NewProperties = @{}
    $NewProperties.Add("Name", [NotionDataModel]::NewTitlePropertyValue($_.Name))
    
    if(-Not $CurrentNotionId){
        $CurrentNotionId = (New-NotionDbPage -secret $secret -db $db -properties $NewProperties ).id
        $CurrentNotionId | Out-File -FilePath $CurrentNotionIdFile
    }
    $ValidNotionPageIds+= $CurrentNotionId
}

$RemotePages | Where-Object {$_.id -notin $ValidNotionPageIds} | ForEach-Object{
    Remove-NotionDbPage -secret $secret -page $_.id
}


# Calculate new Notion DB schema
[NotionPropertySchemaCollection]$NewDbSchema = @{}

$Checks | ForEach-Object{
    switch($_.Type){
        "Checkbox"{
            $NewPropertySchema = [NotionDataModel]::CheckboxSchema
        }
        "Text"{
            $NewPropertySchema = [NotionDataModel]::RichTextSchema
        }
        "Number"{
            $NewPropertySchema = [NotionDataModel]::NumberSchema
        }
        default{
            Write-Error "No Schema for $($_.BaseName)"
        }
    }
    $NewDbSchema[".$($_.Name)"] = $NewPropertySchema
}

# Get Old Notion DB schema

[NotionPropertySchemaCollection]$OldDbSchema = @{}

$NotionDb = Get-NotionDb -secret $secret -db $db
$NotionDb.properties | Get-Member | ?{$_.Name -like ".*"} | ForEach{
    $OldDbSchema.Add($_.Name,$null)
}

# Replace new schema into old schema

[NotionPropertySchemaCollection]$UpdateSchema = $OldDbSchema

$NewDbSchema.Keys | ForEach-Object{
    $UpdateSchema[$_] = $NewDbSchema[$_]
}

# Apply the new schema to the Database

Update-NotionDbSchema -secret $secret -db $db -Schema $UpdateSchema


# Run checks inside folders

$LocalDirectories | ForEach-Object{
    $CurrentDirectory = $_
    $CurrentNotionId = Get-Content "$($CurrentDirectory.FullName)/id.notion"

    [NotionPropertyCollection]$NewProperties = @{}
    $NewProperties.Add("Name", [NotionDataModel]::NewTitlePropertyValue($_.Name))
    if(-Not $CurrentNotionId){
        $CurrentNotionId = (New-NotionDbPage -secret $secret -db $db -properties $NewProperties ).id
        $CurrentNotionId | Out-File -FilePath $CurrentNotionIdFile
    }

    $Checks | ForEach-Object{
        $CurrentCheck = $_
        try{
            $Result = (& $CurrentCheck.ScriptPath $CurrentDirectory.FullName | Select-Object -Last 1)
        }catch{
            Write-Warning "$CurrentDirectory could not be processed: $_"
            $Result = $false
        }

        switch($_.Type){
            "Checkbox"{
                $NewProperties[".$($CurrentCheck.Name)"]=[NotionDataModel]::NewCheckboxProperty($Result)
            }
            "Text"{
                $NewProperties[".$($CurrentCheck.Name)"]=[NotionDataModel]::NewRichTextProperty($Result)
            }
            "Number"{
                $NewProperties[".$($CurrentCheck.Name)"]=[NotionDataModel]::NewNumberProperty($Result)
            }
            default{
                Write-Error "No Schema for $($_.BaseName)"
            }
        }
        
    }
    Write-Host -ForegroundColor Yellow "New Properties:"
    $NewProperties | ConvertTo-Json -Depth 100
    Update-NotionDbPage -secret $secret -page $CurrentNotionId -properties $NewProperties

}