# Directories-to-Notion
 
**Directories-to-Notion (DtN)** is a powershell script which turns directories on disk into [Notion](https://notion.so) database pages. One directory represents the database and every subdirectory immediately contained within it becomes one page. Custom properties can be added using simple powershell scripts.

DtN was written to keep track of all the production files and their various stages for the 3D asset website [ambientCG](https://ambientcg.com), but it is very flexible and can be adapted to work for any scenario where one has a bunch of tasks, all with a similar workflow, each of which is represented by one folder. 
An example would be the ongoing productions for a YouTube channel where every video has raw footage, converted footage, a thumbnail and other project files grouped in one folder. DtN can automatically create a Notion database showing which steps still need to be done for each video.

# Basic Setup
Setting up the script requires creating a new Notion integration
1. Download or clone the file `Sync-DirectoriesToNotion.ps1` and save it in a new folder.
2. Go to the [Notion API Integrations page](https://www.notion.so/my-integrations) and create a new Integration. 
Choose a name and workspace allow the integration to *read, update and insert content* (All checkboxes). Set **User Capabilities** to 'No user information'.
3. Submit the form. You will then receive an **Internal Integration Token** - a short text string that looks like `secret_123...`.
4. Create a new database in the Notion workspace you gave the integration access to. Click on **Share** and "invite" the integration as an editor.
5. Get the database ID which is contained in the url of the page. The ID is the random string of numbers *between the last slash (/) and the question mark (or the end of the url).*
```
https://www.notion.so/myworkspace/309476359187414319cb9912e6585f48
                                 |           Database ID          |

https://www.notion.so/myworkspace/309476359187414319cb9912e6585f48?v=fe3f5e16cc05406c18ac00296ffba5e7
                                 |           Database ID          |
```
6. You now have all the information you need to sync a directory to Notion. Start the script like this:

```
PS> ./Invoke-NotionDirectorySync.ps1 -NotionDatabase <Database ID> -NotionSecret <Secret String> -Directory "C:/Your/Target/Directory"
```
Every directory will be turned into a Notion card. The id gets saved into a file called `id.notion` inside every directory. This allows the script to keep track of a directory even if it is renamed.

# Adding Properties to the Database
You can add properties to the database to perform automatic checks on your files. This could be used to count the number of photos in a folder, check whether a specific file as been created already or get the size of a file.

## Creating Check Scripts
These "check scripts" must be in one folder and their name determines the type and name of the database property that will be created for them. The pattern works like this:
```
[Type]-[Name].ps1
```
`[Type]` can be `Text`, `Number` or `Checkbox`.
`[Name]` represents the name of the property.
Here are a few examples for possible file names:
```
Checkbox-ThumbnailExists.ps1
Number-NumberOfPhotos.ps1
Text-Latest Log Entry.ps1 # Spaces are allowed, just not around the dash (-).
```
## Writing the Scripts
Inside every script file you can now add your code to perform the check on the directory. When writing the script you can assume that the **full path to the directory** will be contained in the `$args[0]` variable. Write your result to the standard output using `Write-Output` (Do not use `Write-Host`, it won't work.).
Here is an example. This script checks if a file called `HelloWorld.txt` exists in every directory and sets the checkbox on every Notion page accordingly.
```
# Checkbox-ContainsHelloWorldFile.ps1

$Result =  Test-Path -Path "$($args[0])/HelloWorld.txt" -PathType Leaf
Write-Output $Result
```
Every property created by this script is prefixed with a dot. This way you can still add you own properties and manually update them without interfering with the automation.
You can find more example scripts in the `checks.example` folder in this repository.
## Running the Scripts
To run the checks, simply exand your call to the main script with the `-CheckScriptsDirectory` parameter which should point to the folder containing all the scripts:

```
PS> ./Invoke-NotionDirectorySync.ps1 -NotionDatabase <Database ID> -NotionSecret <Secret String> -Directory "C:/Your/Target/Directory" -CheckScriptsDirectory $PSScriptRoot/checks
```