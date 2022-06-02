class NotionProperty{
    static [PsCustomObject] $Schema = @{}
    static [PsCustomObject] NewProperty(){return @{}}
}
class NotionPropertyValue : PSCustomObject {}
class NotionPropertySchema : PSCustomObject {}

class NotionRichTextProperty : NotionProperty {
    static [NotionPropertySchema] $Schema = @{
        "rich_text" = @{}
    }
    static [NotionPropertyValue] NewProperty ([string]$Text){
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
}

class NotionTitleProperty : NotionProperty {
    static [NotionPropertySchema] $Schema = @{
        "title" = @{}
    }
    static [NotionPropertyValue] NewProperty ([String]$Title){
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
}

class NotionNumberProperty : NotionProperty {
    static [NotionPropertySchema] $Schema = @{
        "number" = @{}
    }
    static [NotionPropertyValue] NewProperty ([System.ValueType]$Number){
        return @{
            "number" = $Number
        }
    }
}



class NotionCheckboxProperty : NotionProperty{
    static [NotionPropertySchema] $Schema = @{
        "checkbox" = @{}
    }
    static [NotionPropertyValue] NewProperty ([Boolean]$Checked){
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

function Update-NotionDbSchemaProperty{
    param(
        [String]$secret,
        [String]$db,
        [String]$PropertyName,
        [PsCustomObject]$Schema
    )

    $Body = @{
        "properties" = @{
            ".$PropertyName" = $Schema
        }
    }

    Invoke-NotionApiRequest -Version "2022-02-22" -Endpoint "https://api.notion.com/v1/databases/$db" -Secret $secret -Method Patch -Body $Body
}

function New-NotionDbPage{
    param(
        [String] $secret,
        [String] $db,
        [Hashtable]$Properties = @{}
    )

    $ConvertedProperties = @{}

    if($Properties){
        $Properties.Keys | Where-Object{$_ -ne ""} | ForEach-Object{
            if($_ -eq "Name"){
                $NotionPropertyName = "Name"
            }else{
                $NotionPropertyName = ".$_"
            }
            $ConvertedProperties.Add($NotionPropertyName,[NotionPropertyValue]$Properties[$_])
        }
    }

    $Body = @{
        "parent" = @{
            "database_id" = "$db"
        }
        "properties" = $ConvertedProperties
    }

    Invoke-NotionApiRequest -Secret $secret -Version "2022-02-22" -Endpoint "https://api.notion.com/v1/pages" -Method Post -Body $Body
}

function Update-NotionDbPage{
    param(
        [String] $secret,
        [String] $page,
        [Hashtable]$Properties = @{}
    )

    $ConvertedProperties = @{}

    if($Properties){
        $Properties.Keys | Where-Object{$_ -ne ""} | ForEach-Object{
            if($_ -eq "Name"){
                $NotionPropertyName = "Name"
            }else{
                $NotionPropertyName = ".$_"
            }
            $ConvertedProperties.Add($NotionPropertyName,[NotionPropertyValue]$Properties[$_])
        }
    }

    $Body = @{
        "parent" = @{
            "database_id" = "$db"
        }
        "properties" = $ConvertedProperties
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