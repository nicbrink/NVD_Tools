#NVD XML Loading Tool
#Created 7/18/2014
#Updated 8/28/2014
#brinkn@nationwide.com

#Used to populate an sqlite database with vulnerability data
##NOTE:  Do to issues with files with brackets[] in the name.  Please dont load a file with brackets

##TODO
#Break it out to populate both vulnerability and product data
#Figure a way to deal with the bracket problem in file names


##Inputs
[CmdletBinding(DefaultParametersetName="XMLFile")]
param(	[switch]$help,
		[string]$DatabaseFile,									#The database to store data in
		[Parameter(ParameterSetName='XMLFile')][string]$XMLFile="",	#The XML File to read in
		[Parameter(ParameterSetName='directory')][string]$directory="", #A whole directory to read in
		[string]$scriptpath = $MyInvocation.MyCommand.Path, 	#The directory to store files
		[switch]$Access = $false,								#Use and access db instead of sqlite
		[switch]$CreateWFN = $false								#Use and process all cpes
	)


##Load Assemblies
[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
[Reflection.Assembly]::LoadFile("C:\MyStuff\TestDev\PowerShellScripts\NWNVD\CPE.dll") |out-null
import-module SQLite #http://psqlite.codeplex.com/

##Variables
$Filter = 'All Files|*.*'
$connection = ''	#Holds the reference to an access database connection

##Functions
function Write-HelpMessage(){
	$USAGE='NVD CVE & CPE Importer .01
Read in a list of files and search a drive for them.  Gathering hash, signature info, and location data.
Created by brinkn@nationwide.com

	Parameters:             
	-Help                          (This Message)
	-DatabaseFile    <FILENAME>      (Name of File to Save Results to.  Must be created already)
	-XMLFile     	 <FILENAME>      (Name of File to Readin. Can be CPE or NVD file)
	-Directory     	 <Directory>     (Name of Directory to Readin. Will attempt to read in all XML files)
	-Access     	 			     (Set this flag to use an access accdb file instead of an sqlite file)
	-CreateWFN						 (Set this flag to runa querry to get all CPEs and populate WFN table)

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
Function GetDirectoryLocation($StartDirectory, $Filter, $Title){
	#Powershell tip of the day
	#http://www.powershellmagazine.com/2013/06/28/pstip-using-the-system-windows-forms-folderbrowserdialog-class/
	#Built on the file selector from above, designed to get a folder name.  With return just the selected path
	$dialog = New-Object -TypeName System.Windows.Forms.FolderBrowserDialog

	$dialog.ShowNewFolderButton = $false
	#$dialog.rootFolder = $StartDirectory
	$dialog.selectedpath = $StartDirectory
	$dialog.Description = $title

	$result = $dialog.ShowDialog()
	if ($result = 'OK')
	{
		return $dialog.selectedpath
	} 
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
	Write-verbose $strSQL
	write-verbose "Time Elapsed: $($sw1.Elapsed)"
	return $dt

}

Function PopulateCVETable2($NVD){
#Created to improve DB performance per a comment on this page
#http://psqlite.codeplex.com/wikipage?title=Using%20Transactions&referringTitle=Documentation
#Going to attempt to add in 100 unit batches
#Adds Data to the CVE Table
$i = 0  #Simple counter
$myString = ""
foreach ($myChild in $NVD.nvd.entry){
	$score = $myChild.cvss.'base_metrics'.score
	$Severity = "LOW"
	$Summary = $myChild.summary.replace("'","")
	if([single]$score -ge 4) {$Severity = "MEDIUM"}
	if([single]$score -ge 7) {$Severity = "HIGH"}
	#build a string to later send to the db
	$mySQL = "insert into CVE( cve_id,published,modified,summary,score,severity,
		vector,complexity,authentication,confidentiality,integrity,availability,cwe ) 
		values( `'$($myChild.'cve-id')`',
		`'$($myChild.'published-datetime')`',
		`'$($myChild.'last-modified-datetime')`',
		`'$Summary`',
		`'$($myChild.cvss.'base_metrics'.score)`',
		`'$Severity`',
		`'$($myChild.cvss.'base_metrics'.'access-vector')`',
		`'$($myChild.cvss.'base_metrics'.'access-complexity')`',
		`'$($myChild.cvss.'base_metrics'.'authentication')`',
		`'$($myChild.cvss.'base_metrics'.'confidentiality-impact')`',
		`'$($myChild.cvss.'base_metrics'.'integrity-impact')`',
		`'$($myChild.cvss.'base_metrics'.'availability-impact')`',
		`'$($myChild.cwe.'id')`');"
	
	$myString = $myString + $mySQL
	if ($Access){
			$cmd = New-Object System.Data.OleDb.OleDbCommand($mySQL, $connection) 
 			$cmd.ExecuteNonQuery() | Out-Null
	}
	$i++
	if(($i % 500) -eq 0){
		InsertRows $myString
		$myString = ""
		#Write-host $i
		}
	}
#Need to write out what is left in the Queue
	InsertRows $myString
	$myString = ""
	Write-host "Total Records Written: $i"

}
Function PopulateApplicationTable2($NVD){
#Created to improve DB performance per a comment on this page
#http://psqlite.codeplex.com/wikipage?title=Using%20Transactions&referringTitle=Documentation
#Going to attempt to add in 100 unit batches
#Adds Data to the Application Table
$i = 0  #Simple counter
$myString = ""
foreach ($myChild in $NVD.nvd.entry){
	foreach ($myAppl in $myChild.'vulnerable-software-list'.product){
		#build a string to later send to the db
		$mySQL = "insert into Application( cve_id,cpe ) 
			values( `'$($myChild.'cve-id')`',
			`'$($myAppl)`' );"
		$myString = $myString +$mySQL
		if ($Access){
			$cmd = New-Object System.Data.OleDb.OleDbCommand($mySQL, $connection) 
 			$cmd.ExecuteNonQuery() | Out-Null
		}
			$i++
		if(($i % 500) -eq 0){
			InsertRows $myString
			$myString = ""
			#Write-host $i
			}
		}
	}
#Need to write out what is left in the Queue
	InsertRows $myString
	$myString = ""
	Write-host "Total Records Written: $i"

}
Function PopulateReferenceTable2($NVD){
#Created to improve DB performance per a comment on this page
#http://psqlite.codeplex.com/wikipage?title=Using%20Transactions&referringTitle=Documentation
#Going to attempt to add in 100 unit batches
#Adds Data to the Application Table
$i = 0  #Simple counter
$myString = ""
foreach ($myChild in $NVD.nvd.entry){
	foreach ($myRef in $myChild.'references'){
		#build a string to later send to the db
		$mySQL = "insert into Reference( cve_id,type,source,reference ) 
			values( `'$($myChild.'cve-id')`',
			`'$($myRef.'reference_type')`',
			`'$($myRef.'source')`',
			`'$($myRef.'reference'.'href')`' );"
		$myString = $myString + $mySQL
		if ($Access){
			$cmd = New-Object System.Data.OleDb.OleDbCommand($mySQL, $connection) 
	 		$cmd.ExecuteNonQuery() | Out-Null
		}
			$i++
		if(($i % 500) -eq 0){
			InsertRows $myString
			$myString = ""
			#Write-host $i
			}
		}
	}
#Need to write out what is left in the Queue
	InsertRows $myString
	$myString = ""
	Write-host "Total Records Written: $i"

}
Function PopulateCPETable2($NVD){
#Created to improve DB performance per a comment on this page
#http://psqlite.codeplex.com/wikipage?title=Using%20Transactions&referringTitle=Documentation
#Going to attempt to add in 100 unit batches
#Adds Data to the CPE Table
$i = 0  #Simple counter
$myString = ""
foreach ($myChild in $NVD.'cpe-list'.'cpe-item'){
		#build a string to later send to the db
		#some titles have a sigle quote "'" causing issues
		$myTitle = $myChild.title.'#text'.Replace("'","")
		$myCPE23 = $myChild.'cpe23-item'.name.Replace("'","''")
		$mySQL = "insert into CPE( cpe,title,reference,cpe23 ) 
			values( `'$($myChild.'name')`',
			`'$($myTitle)`' ,
			`'$($myChild.reference)`' ,
			`'$($myCPE23)`' );"
			$myString = $myString + $mySQL
		if ($Access){
			$cmd = New-Object System.Data.OleDb.OleDbCommand($mySQL, $connection) 
 			$cmd.ExecuteNonQuery() | Out-Null
		}
			$i++
		if(($i % 500) -eq 0){
			try {
				InsertRows $myString
			}
			catch [system.exception]
			{
				Write-Host $myString
			}
			$myString = ""
			#Write-host $i
			}
	}
#Need to write out what is left in the Queue
	InsertRows $myString
	$myString = ""
	Write-host "Total Records Written: $i"

}

Function PopulateWFNTable2($NVD){
#Created to improve DB performance per a comment on this page
#http://psqlite.codeplex.com/wikipage?title=Using%20Transactions&referringTitle=Documentation
#Going to attempt to add in 100 unit batches
#Adds Data to the CPE Table
$i = 0  #Simple counter
$myString = ""
foreach ($myChild in $NVD.'cpe-list'.'cpe-item'){
		#build a string to later send to the db
		#some titles have a sigle quote "'" causing issues
		#$item contains each CPE, need to turn this into a WFN 
		$objRecord = New-Object System.Object
		$myWFN = [CPE.CPENameUnbinder]::unbindURI($myChild.'name')
		$objRecord = $myWFN.myWFN

		$mySQL = "insert into WFN( cpe,part,vendor,product,version,[update],edition,[language],sw_edition,target_sw,target_hw,other ) 
			values( `'$($myChild.'name')`',
			`'$($objRecord.PART.Replace(""_"","" ""))`' ,
			`'$($objRecord.VENDOR.Replace(""\"",""""))`' ,
			`'$($objRecord.PRODUCT.Replace(""\"",""""))`' ,
			`'$($objRecord.version.Replace(""\"",""""))`' ,
			`'$($objRecord.UPDATE.Replace(""0"",""""))`' ,
			`'$($objRecord.EDITION.Replace(""0"",""""))`' ,
			`'$($objRecord.LANGUAGE.Replace(""0"",""""))`' ,
			`'$($objRecord.SW_EDITION.Replace(""0"",""""))`' ,
			`'$($objRecord.TARGET_SW.Replace(""0"",""""))`' ,
			`'$($objRecord.TARGET_HW.Replace(""0"",""""))`' ,
			`'$($objRecord.OTHER.Replace(""0"",""""))`');"
			$myString = $myString + $mySQL
		if ($Access){
			$cmd = New-Object System.Data.OleDb.OleDbCommand($mySQL, $connection) 
 			$cmd.ExecuteNonQuery() | Out-Null
		}
			$i++
		if(($i % 500) -eq 0){
			try {
				InsertRows $myString
			}
			catch [system.exception]
			{
				Write-Host $myString
			}
			$myString = ""
			#Write-host $i
			}
	}
#Need to write out what is left in the Queue
	InsertRows $myString
	$myString = ""
	Write-host "Total Records Written: $i"

}
Function ProcessAllWFN($NVD){
#Found that the CVE's have CPEs that are not in the full CPE catalog.  This runs
#a query to get CPE's that are not in the application table
#odds are this will not work with SQLite because of its join problems
$connection = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$DatabaseFile")
 $connection.Open()
		
#Run a Query
$cpeQuery = 'SELECT DISTINCT Application.cpe
FROM Application LEFT JOIN WFN ON Application.[cpe] = WFN.[cpe]
WHERE (((WFN.cpe) Is Null));'

$myData = AccessRunQuery($cpeQuery)

$i = 0  #Simple counter
$myString = ""
foreach ($item in $myData){
		#build a string to later send to the db
		#some titles have a sigle quote "'" causing issues
		#$item contains each CPE, need to turn this into a WFN 
		$objRecord = New-Object System.Object
		$myWFN = [CPE.CPENameUnbinder]::unbindURI($item.cpe)
		$objRecord = $myWFN.myWFN
		
		$myVendor = $objRecord.VENDOR.Replace("\","")
		$myVendor = $myVendor.Replace("'","")		
		$myProduct = $objRecord.PRODUCT.Replace("\","")
		$myProduct = $myProduct.Replace("'","")
		
		$mySQL = "insert into WFN( cpe,part,vendor,product,version,[update],edition,[language],sw_edition,target_sw,target_hw,other ) 
			values( `'$($item.cpe)`',
			`'$($objRecord.PART.Replace(""_"","" ""))`' ,
			`'$myVendor`' ,
			`'$myProduct`' ,
			`'$($objRecord.version.Replace(""\"",""""))`' ,
			`'$($objRecord.UPDATE.Replace(""0"",""""))`' ,
			`'$($objRecord.EDITION.Replace(""0"",""""))`' ,
			`'$($objRecord.LANGUAGE.Replace(""0"",""""))`' ,
			`'$($objRecord.SW_EDITION.Replace(""0"",""""))`' ,
			`'$($objRecord.TARGET_SW.Replace(""0"",""""))`' ,
			`'$($objRecord.TARGET_HW.Replace(""0"",""""))`' ,
			`'$($objRecord.OTHER.Replace(""0"",""""))`');"
			$myString = $myString + $mySQL
		if ($Access){
			$cmd = New-Object System.Data.OleDb.OleDbCommand($mySQL, $connection) 
 			$cmd.ExecuteNonQuery() | Out-Null
		}
			$i++
		if(($i % 500) -eq 0){
			try {
				InsertRows $myString
			}
			catch [system.exception]
			{
				Write-Host $myString
			}
			$myString = ""
			#Write-host $i
			}
	}
#Need to write out what is left in the Queue
	InsertRows $myString
	$myString = ""
	Write-host "Total Records Written: $i"

}

Function PopulateMTFTable2($MTF){
#Created to improve DB performance per a comment on this page
#http://psqlite.codeplex.com/wikipage?title=Using%20Transactions&referringTitle=Documentation
#Going to attempt to add in 100 unit batches
#Adds McAfee Threat Feed Data to the MTF Table
$i = 0  #Simple counter
$objRecord = New-Object System.Object
$myString = ""
$myCVE = ""
$myRecommendation = ""
$myVector = ""
foreach ($reference in $MTF.'mcAfeeThreat'.'externalReferences'.reference){
	if (($reference.'type'.Replace("'","")-eq "CVE")){
		$myCVE = $reference.'#text'.Replace("'","")
		
		$myRecommendation = $MTF.'mcAfeeThreat'.'recommendation'
		
		foreach ($mitigation in $MTF.'mcAfeeThreat'.'mitigations'){
			#Write-Host "$myCVE : $($mitigation.'mitigation'.'vector')"
			$myVector = $mitigation.'mitigation'.'vector'
			
			foreach ($product in $mitigation.'mitigation'.'descriptors'.'group'.'productDescriptor'){
				if(($product.id -eq 5) -or ($product.id -eq 17) -or ($product.id -eq 16)-or ($product.id -eq 19)){
					#Write a record to Database.
					
					#Write-Host $product.id
					$objRecord = New-Object System.Object
					$objRecord | Add-Member -NotePropertyName CVE -NotePropertyValue $reference.'#text'.Replace("'","")
					$objRecord | Add-Member -NotePropertyName Recommendation -NotePropertyValue $MTF.'mcAfeeThreat'.'recommendation'
					$objRecord | Add-Member -NotePropertyName Vector -NotePropertyValue $mitigation.'mitigation'.'vector'
					$objRecord | Add-Member -NotePropertyName ID -NotePropertyValue $product.id
					$objRecord | Add-Member -NotePropertyName ProductName -NotePropertyValue $product.name
					$objRecord | Add-Member -NotePropertyName mitigationCoverage -NotePropertyValue $product.mitigationCoverageStatusDescription
					
					#$objRecord | Select-Object CVE, Recommendation, Vector, ID, ProductName, mitigationCoverage, mitigationCoverageID | Export-Csv -Path C:\MyStuff\TestDev\PowerShellScripts\NWNVD\MTF.csv -Encoding ascii -NoTypeInformation -Append
					#Create SQL to insert into DB
					$mySQL = "insert into MTF( CVE,recommendation,vector,productid,productname,mitigationcoverage ) 
						values( `'$($objRecord.CVE)`',
						`'$($objRecord.Recommendation)`' ,
						`'$($objRecord.vector)`' ,
						`'$($objRecord.id)`' ,
						`'$($objRecord.productname)`' ,
						`'$($objRecord.mitigationcoverage)`' );"
				$myString = $myString + $mySQL
				if ($Access){
					$cmd = New-Object System.Data.OleDb.OleDbCommand($mySQL, $connection) 
		 			$cmd.ExecuteNonQuery() | Out-Null
				}
				}
			}
		}
	}
	}
#Need to write out what is left in the Queue
	InsertRows $myString
	$myString = ""
	Write-host "Total Records Written: $i"

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
				Write-Verbose "Populating WFN Table"
				PopulateWFNTable2($NVD)
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
Function LoadAccess($XMLFiles, $DatabaseFile){
	#Loads the xml file or xml files into an Access database
	#This function is a duplicate of the LoadSQLite function
	#Can probably replaced with one function to prevent duplication
	foreach ($item in $XMLFiles) {
		#attach to db
		$connection = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$DatabaseFile")
 		$connection.Open()

		Write-Host "Loading file $($item.fullname)"
		#Wow, huge speed difference between .LOAD and get-content.
		#http://social.technet.microsoft.com/forums/windowsserver/en-US/b61e2ef8-976d-4a2a-addb-4d45038cc81f/cannot-convert-xml-file
		$NVD = New-Object XML
		$NVD.Load($item.fullname)
		#[xml]$NVD = Get-Content $item.fullname
		
		#Look at content of the XML to determine what kind of file and what we should do
		$myType = $NVD.DocumentElement.Name
		Write-Verbose "XML is of type: $myType"
		#cpe-list
		#nvd
		$ErrorActionPreference ="SilentlyContinue"
		switch($myType){
			cpe-list {
				Write-Verbose "Populating CPE Table"
				#Populate CPE Table
				PopulateCPETable2($NVD)
				Write-Verbose "Populating WFN Table"
				PopulateWFNTable2($NVD)
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
			mcAfeeThreat {
				Write-Verbose "Populating McAfee Threat Feed Table"
				#Populate CPE Table
				PopulateMTFTable2($NVD)
			}
		}
		$ErrorActionPreference ="Continue"
	#added and removing the datbase each pass, becuase it seems to improve performance for SQLite
	#may not be necessary for MS Access
	$connection.Close()
	}

}
##Begin Program
Write-Host "NVD CVE and CPE Importer .01"

##Parameter Checking
#Check if help message was requested
if ($help) {Write-HelpMessage;break}

#determine if we are loading one file, or a directory
Write-verbose $psCmdlet.ParameterSetName
switch ($psCmdlet.ParameterSetName) {
XMLFile {
	#Check if a XML file was provided, if not pop up a window.
	if ($XMLFile.length -le 1) {
		#Since there was not a policy provided on the command line, go ahead and ask for one.
		$scriptpath = $MyInvocation.MyCommand.Path
		$scriptpath = Split-Path $scriptpath
		$XMLFile = GetFileLocation $scriptpath $filter 	"Select XML File to Load" $true #file with policy information
		if ($XMLFile -eq "cancel") {write-host "Exiting..."; exit}
		#build a collection of one file
		$XMLFiles = Get-ChildItem -File $XMLFile

	}
}
Directory {
	#Check if a directory was provided, if not pop up a window.
	if ($directory.length -le 1) {
		#Since there was not a policy provided on the command line, go ahead and ask for one.
		$scriptpath = $MyInvocation.MyCommand.Path
		$scriptpath = Split-Path $scriptpath
		$directory = GetDirectoryLocation $scriptpath $filter "Select XML Directory to Load"
	}
	#Have a directory now, create an array of the files within it
	#build a collection of all files in the directory
	$XMLFiles = Get-ChildItem -Path "$directory" -Filter "*.xml"

}
default {Write-Host  "Should not be here"}
}



#Check if a Database file was provided, if not pop up a window.
if ($DatabaseFile.length -le 1) {
	#Since there was not a policy provided on the command line, go ahead and ask for one.
	$scriptpath = $MyInvocation.MyCommand.Path
	$scriptpath = Split-Path $scriptpath
	$DatabaseFile = GetFileLocation $scriptpath $filter "Select Database to Read Into"	#file with policy information
	if ($DatabaseFile -eq "cancel") {write-host "Exiting..."; exit}
}
#We need to modify the $XMLFile string because of the way powershell handles [] square brackets.
#Note this does not actually work, and should be avoided
$DatabaseFile = $DatabaseFile.Replace('[', '``[').Replace(']', '``]')
$DatabaseFile = Resolve-Path $DatabaseFile #File the full path and ensure if a ..\ is provide we get the right file
Write-Verbose "Database File to read in: $DatabaseFile"

# Check if file exists, if not error out.
if(!(fileexists($DatabaseFile))){Write-Host "The file: $DatabaseFile does not exist";break}


#Start Metrics
$sw = [Diagnostics.Stopwatch]::StartNew()

#Attempt to load XML
Write-Verbose "Loading XML File"
if($CreateWFN){
	ProcessAllWFN $DatabaseFile
	break
}

PopulateMTFTable2
if ($Access) {
	LoadAccess $XMLFiles $DatabaseFile
}else {
	LoadSQLite $XMLFiles $DatabaseFile
}

#Print Metrics
$sw.Stop()
write-verbose "Time Elapsed: $($sw.Elapsed)"
write-host "Time Elapsed: $($sw.Elapsed)"