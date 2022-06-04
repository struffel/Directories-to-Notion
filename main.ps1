
class NotionProperty : PSCustomObject {}
class NotionPropertyCollection : System.Collections.Generic.Dictionary[System.String,PSCustomObject] {}

class NotionPropertySchema : PSCustomObject {}
class NotionPropertySchemaCollection :     System.Collections.Generic.Dictionary[System.String,PSCustomObject] {}



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
            "checked" = $Checked
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

# Calculate new Notion DB schema

[NotionPropertySchemaCollection]$NewDbSchema = @{}

Get-ChildItem -Path $ChecksFolder -File -Filter '*.ps1' | ForEach-Object{
    $NewPropertyName = $_.BaseName.split('-')[1]
    switch($_.BaseName.split('-')[0]){
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
    $NewDbSchema.Add(".$NewPropertyName",$NewPropertySchema)
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


<#
$Prop = @{
    "Name" = [NotionTitleProperty]::NewProperty("Testpage B")
}

$Response = New-NotionDbPage -secret $secret -db $db -Properties $Prop

$Prop = @{
    "NETtoTifDevelopment" = [NotionRichTextProperty]::NewProperty("1234")
}

Update-NotionDbPage -secret $secret -page $Response.id -Title "Testpage C" -Properties $Prop
#>

#Update-NotionDbSchemaProperty -secret $secret -db $db -PropertyName "mytest" -Schema $null





<#
Get-ChildItem -Filter "*_HDRI" "T:\WIP" | ForEach-Object{
    $CurrentDirectory = $_
    Write-Host -ForegroundColor Green $CurrentDirectory

    try{
        $Result = (& "$PSScriptRoot\checks\Checkbox-NEFtoTIFDevelopment.ps1" $CurrentDirectory.FullName | Select-Object -Last 1)
        $Result = [Boolean]$Result
    }catch{
        Write-Warning "$CurrentDirectory could not be processed: $_"
        $Result = $false
    }

    
    $Result
}

#>