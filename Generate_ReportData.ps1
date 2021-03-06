#NVD Data Generating Tool
#Created 9/4/2014
#brinkn@nationwide.com

#This will take the data we have already gathered and populate the WFN table of the database.  It will also generate a csv summary of all CPE / CVE information

##TODO
#This is the final version of the Generate_WFNs_inDatabase.ps1 which was a proof of concept code.
#Need to add creation of the WFN table to the generate database table


##Inputs
param(	[switch]$help,
		[string]$DatabaseFile,									#The database to store data in
		[string]$scriptpath = $MyInvocation.MyCommand.Path, 	#The directory to store files
		[switch]$Access = $false								#Use and access db instead of sqlite
	)


##Load Assemblies
[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
[Reflection.Assembly]::LoadFile("C:\MyStuff\TestDev\PowerShellScripts\NWNVD\CPE.dll") |out-null
import-module SQLite #http://psqlite.codeplex.com/

##Variables
$Filter = 'All Files|*.*'
$connection = ''	#Holds the reference to an access database connection
$cpeQuery = "select * from CPE"
$cveQuery = "SELECT C.cve_id,C.score as Score, C.severity as Severity , A.cpe 
     FROM CVE C      
          JOIN (SELECT cpe,cve_id
              FROM Application 
               ) A ON C.cve_id = A.cve_id where a.cpe = "
$cveQuery = "SELECT C.cve_id,C.score as Score, C.severity as Severity , A.cpe 
     FROM CVE C      
          INNER JOIN (SELECT cpe,cve_id
              FROM Application 
               ) A ON C.cve_id = A.cve_id where a.cpe = "
$nvdURL = "http://web.nvd.nist.gov/view/vuln/search-results?adv_search=true&cves=on&cpe_version="

##Functions
function Write-HelpMessage(){
	$USAGE='NVD Data Generating Tool v1.0
Takes a populated database and generates WFNs from the CPE table.
Created by brinkn@nationwide.com

	Parameters:             
	-Help                          (This Message)
	-DatabaseFile    <FILENAME>      (Name of File to Save Results to.  Must be created already)
	-Access     	 			     (Set this flag to use an access accdb file instead of an sqlite file)

	        '
	Write-host $usage
}
Function FileExists {
	Param(
		[string]$FileName="")  #Name of file to check
	Write-Verbose "Checking for existance of $FileName"
	$result = Test-Path -path $FileName 
	if ($result){Write-Verbose "The file $FileName exists."}else{Write-Verbose "The file $FileName does not exist."}
	return $result
}
Function GetFileLocation($StartDirectory, $Filter, $Title){
	#Powershell tip of the day
	#http://s1403.t.en25.com/e/es.aspx?s=1403&e=85122&elq=7b9bf21b612743dea14c73c513d956f9
	$dialog = New-Object -TypeName System.Windows.Forms.OpenFileDialog

	$dialog.AddExtension = $true
	$dialog.Filter = $filter
	$dialog.Multiselect = $Multi
	$dialog.FilterIndex = 0
	$dialog.InitialDirectory = $StartDirectory
	$dialog.RestoreDirectory = $true
	#$dialog.ShowReadOnly = $true
	$dialog.ReadOnlyChecked = $false
	$dialog.Title = $Title

	$result = $dialog.ShowDialog()
	if ($result -eq 'OK')
	{
	    $filename = $dialog.FileName
	    $readonly = $dialog.ReadOnlyChecked
	    if ($readonly) { $mode = 'read-only' } else {$mode = 'read-write' }
		return $filename
	} else {return "cancel"}
}
Function GetStats {
	Param(
		[object]$Scores)
	Write-Verbose "Counting number of CVE's and their scores"
	$objRecord = New-Object System.Object
	$High = 0
	$Medium = 0
	$Low = 0
	$Score_String = ""
	
	foreach($score in $Scores){
		switch ($score.Severity) 
		    { 
		        HIGH {$High++} 
		        MEDIUM {$Medium++} 
		        LOW {$Low++} 
		        default {}
		    }
		$Score_String = $score_String + ":" + $score.Score

	}
	if($High -eq 0){$HIGH ="-"}
	if($Medium -eq 0){$Medium ="-"}
	if($Low -eq 0){$Low ="-"}
	$objRecord | Add-Member -NotePropertyName HIGH -NotePropertyValue $HIGH
	$objRecord | Add-Member -NotePropertyName MEDIUM -NotePropertyValue $MEDIUM
	$objRecord | Add-Member -NotePropertyName LOW -NotePropertyValue $LOW
	$objRecord | Add-Member -NotePropertyName SCORES -NotePropertyValue $Score_String
	return $objRecord
}

Function AccessRunQuery($strSQL){
	#http://poshcode.org/1591
	#Start Metrics
$sw1 = [Diagnostics.Stopwatch]::StartNew()
	$connection = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$DatabaseFile")
	$connection.Open()
	$cmd = New-Object System.Data.OleDb.OleDbCommand($strSQL, $connection) 
	$da = New-Object system.Data.OleDb.OleDbDataAdapter($cmd)
   	$dt = New-Object system.Data.datatable
	[void]$da.fill($dt)
	$sw1.Stop()
	Write-Host $strSQL
	write-host "Time Elapsed: $($sw1.Elapsed)"
	return $dt

}


Function InsertRows($strSQL){
	#Will execute passed SQL statments against a database.  The goal is to create the SQL once and 
	#execute against msaccess or sqlite as necessary.
	#assumes the database connection exists and is open
	if($Access) {
		#$ErrorActionPreference ="Inquire"
		#$strSQL.split(";") | foreach {
		#	$cmd = New-Object System.Data.OleDb.OleDbCommand($_, $connection) 
 		#	$cmd.ExecuteNonQuery()	
		#}
		#$ErrorActionPreference = "Continue"
	}else {
		invoke-item NVDDB: -sql $strSQL
	}
}

Function LoadSQLite($XMLFiles, $DatabaseFile){
	#Loads the xml file or xml files into an sqlite database
	foreach ($item in $XMLFiles) {
		#attach to db
		mount-sqlite -name NVDDB -dataSource $DatabaseFile

		Write-Host "Loading file $($item.fullname)"
		$NVD = New-Object XML
		$NVD.Load($item.fullname)
		
		#Look at content of the XML to determine what kind of file and what we should do
		$myType = $NVD.DocumentElement.Name
		Write-Verbose "XML is of type: $myType"
		#cpe-list
		#nvd
		switch($myType){
			cpe-list {
				Write-Verbose "Populating CPE Table"
				#Populate CPE Table
				PopulateCPETable2($NVD)
			}
			nvd {
				Write-Output "Loading File: $XMLFile"
				#Populate CVE Data
				Write-Verbose "Populating CVE Table"
				PopulateCVETable2($NVD)
				#Populate Application table
				Write-Verbose "Populating Application"
				PopulateApplicationTable2($NVD)
				Write-Verbose "Populating Reference Table"						
				PopulateReferenceTable2($NVD)
		 	}	
		}
	#added and removing the datbase each pass, becuase it seems to improve performance
	Remove-PSDrive NVDDB
	}
}
Function LoadAccess($DatabaseFile){
	#Loads an Access Database and populates the WFN table.
	#This function is a duplicate of the LoadSQLite function
	#Can probably replaced with one function to prevent duplication

	$myData = AccessRunQuery($cpeQuery)

	$connection = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$DatabaseFile")
	$connection.Open()


	foreach($item in $myData){
		#Clear some Vars
		$myScores = ""

		#Create a container for our excel row
		$objRecord = New-Object System.Object
		
		#$item contains each CPE, need to turn this into a WFN for the excel file
		$myWFN = [CPE.CPENameUnbinder]::unbindURI($item.cpe)
		$objRecord = $myWFN.myWFN
		
		#Get a count of High, Medium and Low, and create an array of scores.
		$testsql = $cveQuery + "'" + $item.cpe +"'"
		#the @() is to force the return of a collection, even if empty

				$sw1 = [Diagnostics.Stopwatch]::StartNew()
				$cmd = New-Object System.Data.OleDb.OleDbCommand($testsql, $connection) 
				$da = New-Object system.Data.OleDb.OleDbDataAdapter($cmd)
			   	$dt = New-Object system.Data.datatable
				[void]$da.fill($dt)
				$sw1.Stop()
				#Write-Host $testsql
				write-host "Time Elapsed: $($sw1.Elapsed)"
		
		$myScores = @($dt)
		
		$objRecord | Add-Member -NotePropertyName CPE -NotePropertyValue $item.cpe
		#get list of scores
		if ($myScores.Count -gt 0) {
			$myResult = GetStats $myScores
			$objRecord | Add-Member -NotePropertyName HIGH -NotePropertyValue $myResult.HIGH
			$objRecord | Add-Member -NotePropertyName MEDIUM -NotePropertyValue $myResult.MEDIUM
			$objRecord | Add-Member -NotePropertyName LOW -NotePropertyValue $myResult.LOW
			$objRecord | Add-Member -NotePropertyName SCORES -NotePropertyValue $myResult.Scores.substring(1)
			$myReference = $nvdURL + $item.cpe
			$objRecord | Add-Member -NotePropertyName REFERENCE -NotePropertyValue $myReference
		}
		#replace \ with nothing, repalce underscore with space to improve readability
		$objRecord.VENDOR = $objRecord.VENDOR.Replace("\","")
		$objRecord.PRODUCT = $objRecord.PRODUCT.Replace("\","")
		$objRecord.VENDOR = $objRecord.VENDOR.Replace("_"," ")
		$objRecord.PRODUCT = $objRecord.PRODUCT.Replace("_"," ")
		$objRecord.VERSION = $objRecord.version.Replace("\","")
		
		#repalce 0's with blanks.
		$objRecord.UPDATE = $objRecord.UPDATE.Replace("0","")
		$objRecord.EDITION = $objRecord.EDITION.Replace("0","")
		$objRecord.LANGUAGE = $objRecord.LANGUAGE.Replace("0","")
		$objRecord.SW_EDITION = $objRecord.SW_EDITION.Replace("0","")
		$objRecord.TARGET_SW = $objRecord.TARGET_SW.Replace("0","")
		$objRecord.TARGET_HW = $objRecord.TARGET_HW.Replace("0","")
		$objRecord.OTHER = $objRecord.OTHER.Replace("0","")
		
		$objRecord | Select-Object CPE, PART, VENDOR, PRODUCT, VERSION, UPDATE, EDITION, LANGUAGE, SW_EDITION, TARGET_SW, TARGET_HW, OTHER, HIGH, MEDIUM, LOW, SCORES,REFERENCE | Export-Csv -Path C:\MyStuff\TestDev\PowerShellScripts\NWNVD\cpe.csv -Encoding ascii -NoTypeInformation -Append
		#$myWFN.myWFN | Select-Object PART, VENDOR, PRODUCT, VERSION, UPDATE, EDITION, LANGUAGE, SW_EDITION, TARGET_SW, TARGET_HW, OTHER, $test | Export-Csv -Path C:\MyStuff\TestDev\PowerShellScripts\NWNVD\ps_cpe\cpe.csv -Encoding ascii -NoTypeInformation -Append
		$i++
	}
	
	
	
	
	
	
	
	
	
	$connection.Close()


}
##Begin Program
Write-Host "NVD Data Generating Tool v1.0"

##Parameter Checking
#Check if help message was requested
if ($help) {Write-HelpMessage;break}

#Check if a Database file was provided, if not pop up a window.
if ($DatabaseFile.length -le 1) {
	#Since there was not a policy provided on the command line, go ahead and ask for one.
	$scriptpath = $MyInvocation.MyCommand.Path
	$scriptpath = Split-Path $scriptpath
	$DatabaseFile = GetFileLocation $scriptpath $filter "Select Database to Read"	#file with policy information
	if ($DatabaseFile -eq "cancel") {write-host "Exiting..."; exit}
}
#We need to modify the $XMLFile string because of the way powershell handles [] square brackets.
#Note this does not actually work, and should be avoided
$DatabaseFile = $DatabaseFile.Replace('[', '``[').Replace(']', '``]')
$DatabaseFile = Resolve-Path $DatabaseFile #File the full path and ensure if a ..\ is provide we get the right file
Write-Verbose "Database File to read: $DatabaseFile"

# Check if file exists, if not error out.
if(!(fileexists($DatabaseFile))){Write-Host "The file: $DatabaseFile does not exist";break}


#Start Metrics
$sw = [Diagnostics.Stopwatch]::StartNew()

#Attempt to load XML
Write-Verbose "Loading XML File"

if ($Access) {
	LoadAccess $DatabaseFile
}else {
	LoadSQLite $DatabaseFile
}

#Print Metrics
$sw.Stop()
write-verbose "Time Elapsed: $($sw.Elapsed)"
write-host "Time Elapsed: $($sw.Elapsed)"