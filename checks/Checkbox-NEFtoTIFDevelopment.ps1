$Raw = (Get-ChildItem -File -Recurse -Filter "*.NEF" "$($args[0])/Raw").BaseName
$Tif = (Get-ChildItem -File -Recurse -Filter "*.TIF" "$($args[0])/Raw").BaseName

$UndevelopedRaw = (Compare-Object -ReferenceObject $Raw -DifferenceObject $Tif)

$UndevelopedRaw | ForEach-Object{
    Write-Verbose "$($_.InputObject) has not been developed."
}

if(($UndevelopedRaw|Measure-Object).Count -gt 0){
    Write-Output $false
}else{
    Write-Output $true
}

