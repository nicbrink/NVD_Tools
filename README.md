NVD_Tools
=========

Powershell Scripts to Interact with Vulnerability Data Sets

Challenge:
  Many vulnerabilty scanners exists to analyze a system locally or remotly to determine f there are vulnerabilties present.  These scanners are able to do a great job because they can look at both files and configurations of a system to determine if a vulnerability exists.
  This is a different offline approach.  The goal is to identify vulnerable applications given a list.  (For example an export from SCCM or other system management tool)  Once the vulnerabilites are identified the organization can make a determination as to which application upgrades are a priority.


This repository contains powershell scripts to:

* Download NVD Data from NIST
* Download CPE Application information from NIST
* Create a usable vulnerabilty database in MS Access of SQLite format
* Populated either of these databases
* Search data within these databases
* Create a report of vulnerabiltes including application and count of vulnerabilities


CPE - Common Platform Enumeration  - Makes use of Version 2.3
CWE - Common Weakness Enumeration
CVE - Common Vulnerabilty Enumeration - Makes use of Version 2.0

These feeds are located at:
http://nvd.nist.gov/download.cfm
