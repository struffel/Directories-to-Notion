class NotionProperty{
    static [PsCustomObject] $Schema = @{}
    static [PsCustomObject] NewProperty(){return @{}}
}
class NotionRichTextProperty : NotionProperty {
    static [PsCustomObject] $Schema = @{
        "rich_text" = @{}
    }
    static [PsCustomObject] NewProperty ([string]$Text){
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

class NotionNumberProperty : NotionProperty {
    static [PsCustomObject] $Schema = @{
        "number" = @{}
    }
    static [PsCustomObject] NewProperty ([System.ValueType]$Number){
        return @{
            "number" = $Number
        }
    }
}

class NotionCheckboxProperty : NotionProperty{
    static [PsCustomObject] $Schema = @{
        "checkbox" = @{}
    }
    static [PsCustomObject] NewProperty ([Boolean]$Checked){
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

function New-NotionDbPage{}

function Remove-NotionDbPage{}

function Get-NotionDbPage{}

function Update-NotionDbPageProperties{}


$db = "b103cdddd45d43dda84e8cff956d137e"
$secret = Get-Content "$PSScriptRoot/token.secret"

Update-NotionDbSchemaProperty -secret $secret -db $db -PropertyName "mytest" -Schema ([NotionCheckboxProperty]::Schema)

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