$Result =  Test-Path -Path "$($args[0])/HelloWorld.txt" -PathType Leaf
Write-Output $Result