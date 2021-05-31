<#PSScriptInfo

.VERSION 1.1

.GUID d1e8624e-4887-44d5-bf2e-2cc56aaa449b

.AUTHOR Vikas Sukhija

.COMPANYNAME TechWizard

.COPYRIGHT Vikas Sukhija

.TAGS

.LICENSEURI

.PROJECTURI http://techwizard.cloud/2020/08/17/intune-check-particular-app-installation-on-devices

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
http://techwizard.cloud/2020/08/17/intune-check-particular-app-installation-on-devices

.PRIVATEDATA
Update: 8/27/2020 fixe dteh bug of folder creation
#>

<# 

.DESCRIPTION 
 Find and report particular application installed on devices 

#> 
param (
  [Parameter(Mandatory = $true)]
  [string]$Application
  )

function New-FolderCreation
{
  [CmdletBinding()]
  param
  (
    [Parameter(Mandatory = $true)]
    [string]$foldername
  )
	

  $logpath  = (Get-Location).path + "\" + "$foldername" 
  $testlogpath = Test-Path -Path $logpath
  if($testlogpath -eq $false)
  {
    #Start-ProgressBar -Title "Creating $foldername folder" -Timer 10
    $null = New-Item -Path (Get-Location).path -Name $foldername -Type directory
  }
}####new folder creation

function Write-Log
{
  [CmdletBinding()]
  param
  (
    [Parameter(Mandatory = $true,ParameterSetName = 'Create')]
    [array]$Name,
    [Parameter(Mandatory = $true,ParameterSetName = 'Create')]
    [string]$Ext,
    [Parameter(Mandatory = $true,ParameterSetName = 'Create')]
    [string]$folder,
    
    [Parameter(ParameterSetName = 'Create',Position = 0)][switch]$Create,
    
    [Parameter(Mandatory = $true,ParameterSetName = 'Message')]
    [String]$message,
    [Parameter(Mandatory = $true,ParameterSetName = 'Message')]
    [String]$path,
    [Parameter(Mandatory = $false,ParameterSetName = 'Message')]
    [ValidateSet('Information','Warning','Error')]
    [string]$Severity = 'Information',
    
    [Parameter(ParameterSetName = 'Message',Position = 0)][Switch]$MSG
  )
  switch ($PsCmdlet.ParameterSetName) {
    "Create"
    {
      $log = @()
      $date1 = Get-Date -Format d
      $date1 = $date1.ToString().Replace("/", "-")
      $time = Get-Date -Format t
	
      $time = $time.ToString().Replace(":", "-")
      $time = $time.ToString().Replace(" ", "")
      New-FolderCreation -foldername $folder
      foreach ($n in $Name)
      {$log += (Get-Location).Path + "\" + $folder + "\" + $n + "_" + $date1 + "_" + $time + "_.$Ext"}
      return $log
    }
    "Message"
    {
      $date = Get-Date
      $concatmessage = "|$date" + "|   |" + $message +"|  |" + "$Severity|"
      switch($Severity){
        "Information"{Write-Host -Object $concatmessage -ForegroundColor Green}
        "Warning"{Write-Host -Object $concatmessage -ForegroundColor Yellow}
        "Error"{Write-Host -Object $concatmessage -ForegroundColor Red}
      }
      
      Add-Content -Path $path -Value $concatmessage
    }
  }
} #Function Write-Log

####################Load variables and log####################
$log = Write-Log -Name "IntuneDeviceApplication-Log" -folder "logs" -Ext "log"
$Report = Write-Log -Name "IntuneDeviceApplication-Report" -folder "Report" -Ext "csv"
$collection = @()
$graphApiVersion = "beta"
################connect to modules###################
Write-Log -Message "Start............Script" -path $log
try
{
  Connect-MSGraph
  Write-Log -Message "Intune Module Loaded" -path $log
}
catch
{
  $exception = $_.Exception
  Write-Log -Message "Error loading AD/Intune Module Loaded" -path $log -Severity Error 
  Write-Log -Message $exception -path $log -Severity error
  Exit
}

##########process devicess with compliant state as unknown####
try
{
  Write-Log -Message "Start fetching all devices in the enviornment, it could take a while" -path $log 
  $getalldevices = Get-IntuneManagedDevice | Get-MSGraphAllPages 
  Write-Log -Message "Count of devices $($getalldevices.count)" -path $log 
}
catch
{
  $exception = $_.Exception
  Write-Log -Message "Error occured fetching unkown devices" -path $log -Severity Error 
  Write-Log -Message $exception -path $log -Severity error
  Exit
}
###########Remove these devices from Intune#################
$count=0
$getalldevices |
ForEach-Object{
  $mcoll = "" |
  Select-Object id, deviceName, AppName, Appversion, Appid, SizeinByte, enrolledDateTime, lastSyncDateTime, emailAddress, serialNumber, complianceState
  $mcoll.id = $_.id
  $deviceid = $_.id
  $Resource = "deviceManagement/managedDevices" + "/" + "$deviceid" + "?`$expand=detectedApps"
  $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
  $app = Invoke-MSGraphRequest -HttpMethod GET -Url $uri
  $foundApp = $app.detectedApps |
  Where-Object{$_.displayname -like $Application}
  $mcoll.appname = $foundApp.displayname
  $mcoll.Appversion = $foundApp.Version
  $mcoll.SizeInByte = $foundApp.SizeInByte
  $mcoll.Appid = $foundApp.id
  $mcoll.deviceName = $_.deviceName
  $mcoll.enrolledDateTime = $_.enrolledDateTime
  $mcoll.lastSyncDateTime = $_.lastSyncDateTime
  $mcoll.emailAddress = $_.emailAddress
  $mcoll.serialNumber = $_.serialNumber
  $mcoll.complianceState = $_.complianceState
  $collection += $mcoll
  $count=$count+1
  if($_.deviceName){
    Write-Progress -Activity "Finding $Application" -status "$($_.deviceName)" -percentComplete ($count/$getalldevices.count*100)
  }else{
   Write-Progress -Activity "Finding $Application" -status "Device Not Found" -percentComplete ($count/$getalldevices.count*100)
  }
}
$collection | where{$_.appname -like $Application} | Export-Csv $Report -NoTypeInformation
 
Write-Log -Message "Script Finished" -path $log
################################################################################
# SIG # Begin signature block
# MIIccAYJKoZIhvcNAQcCoIIcYTCCHF0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUlTenW4QApBD7gzGI6O/y1sow
# HTugghefMIIFKDCCBBCgAwIBAgIQBBcjfnd2/0lPtk4Ac2XkEzANBgkqhkiG9w0B
# AQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFz
# c3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMB4XDTIwMDcwODAwMDAwMFoXDTIzMDcx
# MzEyMDAwMFowZTELMAkGA1UEBhMCQ0ExEDAOBgNVBAgTB09udGFyaW8xFDASBgNV
# BAcTC01pc3Npc3NhdWdhMRYwFAYDVQQKEw1WaWthcyBTdWtoaWphMRYwFAYDVQQD
# Ew1WaWthcyBTdWtoaWphMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
# 4St8d9DqmfWYRMXs9ampsHh6qVG4kVEaB1AA9GS9itVGUgtkz+18W5mSvpymVX7e
# 795HGUCqR5GfNuJEr6jCaLXZmfDmi3M8m5lFJvqCbV1IZtlN9rLYlcKCVzwvRm2y
# ctcdFSLzB1spKm/15gjyt546JdVtQe5uzvf4Rcf5SUOIIyzsunA/JWPK3mjQkx0F
# ygeN1EiHHVQoQEJ5bLTDOKoNj3inAK7N4NCuxe39R8xbOTXUfZm5/Zdg8MjLQXs2
# zKEPHtsyJ8zRAVYLQLUiKduHwwZS57XyaOWVOlhxLDM1QXXV31XNEbCFnwBTZt63
# xMgB6S3/g/lpYx1P21orUQIDAQABo4IBxTCCAcEwHwYDVR0jBBgwFoAUWsS5eyoK
# o6XqcQPAYPkt9mV1DlgwHQYDVR0OBBYEFMu2/KoMoWIixN8+jbE8OgpMUr6gMA4G
# A1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzB3BgNVHR8EcDBuMDWg
# M6Axhi9odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVkLWNzLWcx
# LmNybDA1oDOgMYYvaHR0cDovL2NybDQuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJl
# ZC1jcy1nMS5jcmwwTAYDVR0gBEUwQzA3BglghkgBhv1sAwEwKjAoBggrBgEFBQcC
# ARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAIBgZngQwBBAEwgYQGCCsG
# AQUFBwEBBHgwdjAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29t
# ME4GCCsGAQUFBzAChkJodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRTSEEyQXNzdXJlZElEQ29kZVNpZ25pbmdDQS5jcnQwDAYDVR0TAQH/BAIwADAN
# BgkqhkiG9w0BAQsFAAOCAQEAT+TncEv203oQo+u4DDHMn6pkTcnzx/W3lrwsjHV+
# C0RcEvTQ0kmpqgqQ1XO3tGhPh3rJAdIUL9M1gUEtSdg4XebJG470va3LTm2hLMbE
# cpSYrkTdpuXEzQ9BO4IaAdWRXzn/VWVeRS79RBRe4RKy8SbvQ5RbfoCUjZ0y6AdG
# ufBhKsSqMEiTyKZRXRcbaw138AkWijQ8J9Gk1UAGPF8l5mYo50p5gFhmlepKYp0n
# tNBJGJE/nRcMPV6BY5Zt8vqpnLGhrdceZkXXwA8JFsS5Z0dkQGvhB8x8jX+xQMUy
# U5/iFTq1Nq/27LFKj7vxDJ8/lgEJ6Y46sp4rBjhi/Q/FGDCCBTAwggQYoAMCAQIC
# EAQJGBtf1btmdVNDtW+VUAgwDQYJKoZIhvcNAQELBQAwZTELMAkGA1UEBhMCVVMx
# FTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNv
# bTEkMCIGA1UEAxMbRGlnaUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4XDTEzMTAy
# MjEyMDAwMFoXDTI4MTAyMjEyMDAwMFowcjELMAkGA1UEBhMCVVMxFTATBgNVBAoT
# DERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UE
# AxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIENvZGUgU2lnbmluZyBDQTCCASIw
# DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAPjTsxx/DhGvZ3cH0wsxSRnP0PtF
# mbE620T1f+Wondsy13Hqdp0FLreP+pJDwKX5idQ3Gde2qvCchqXYJawOeSg6funR
# Z9PG+yknx9N7I5TkkSOWkHeC+aGEI2YSVDNQdLEoJrskacLCUvIUZ4qJRdQtoaPp
# iCwgla4cSocI3wz14k1gGL6qxLKucDFmM3E+rHCiq85/6XzLkqHlOzEcz+ryCuRX
# u0q16XTmK/5sy350OTYNkO/ktU6kqepqCquE86xnTrXE94zRICUj6whkPlKWwfIP
# EvTFjg/BougsUfdzvL2FsWKDc0GCB+Q4i2pzINAPZHM8np+mM6n9Gd8lk9ECAwEA
# AaOCAc0wggHJMBIGA1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0PAQH/BAQDAgGGMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MIGB
# BgNVHR8EejB4MDqgOKA2hjRodHRwOi8vY3JsNC5kaWdpY2VydC5jb20vRGlnaUNl
# cnRBc3N1cmVkSURSb290Q0EuY3JsMDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsME8GA1UdIARIMEYwOAYK
# YIZIAYb9bAACBDAqMCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5j
# b20vQ1BTMAoGCGCGSAGG/WwDMB0GA1UdDgQWBBRaxLl7KgqjpepxA8Bg+S32ZXUO
# WDAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzANBgkqhkiG9w0BAQsF
# AAOCAQEAPuwNWiSz8yLRFcgsfCUpdqgdXRwtOhrE7zBh134LYP3DPQ/Er4v97yrf
# IFU3sOH20ZJ1D1G0bqWOWuJeJIFOEKTuP3GOYw4TS63XX0R58zYUBor3nEZOXP+Q
# sRsHDpEV+7qvtVHCjSSuJMbHJyqhKSgaOnEoAjwukaPAJRHinBRHoXpoaK+bp1wg
# XNlxsQyPu6j4xRJon89Ay0BEpRPw5mQMJQhCMrI2iiQC/i9yfhzXSUWW6Fkd6fp0
# ZGuy62ZD2rOwjNXpDd32ASDOmTFjPQgaGLOBm0/GkxAG/AeB+ova+YJJ92JuoVP6
# EpQYhS6SkepobEQysmah5xikmmRR7zCCBmowggVSoAMCAQICEAMBmgI6/1ixa9bV
# 6uYX8GYwDQYJKoZIhvcNAQEFBQAwYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERp
# Z2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMY
# RGlnaUNlcnQgQXNzdXJlZCBJRCBDQS0xMB4XDTE0MTAyMjAwMDAwMFoXDTI0MTAy
# MjAwMDAwMFowRzELMAkGA1UEBhMCVVMxETAPBgNVBAoTCERpZ2lDZXJ0MSUwIwYD
# VQQDExxEaWdpQ2VydCBUaW1lc3RhbXAgUmVzcG9uZGVyMIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEAo2Rd/Hyz4II14OD2xirmSXU7zG7gU6mfH2RZ5nxr
# f2uMnVX4kuOe1VpjWwJJUNmDzm9m7t3LhelfpfnUh3SIRDsZyeX1kZ/GFDmsJOqo
# SyyRicxeKPRktlC39RKzc5YKZ6O+YZ+u8/0SeHUOplsU/UUjjoZEVX0YhgWMVYd5
# SEb3yg6Np95OX+Koti1ZAmGIYXIYaLm4fO7m5zQvMXeBMB+7NgGN7yfj95rwTDFk
# jePr+hmHqH7P7IwMNlt6wXq4eMfJBi5GEMiN6ARg27xzdPpO2P6qQPGyznBGg+na
# QKFZOtkVCVeZVjCT88lhzNAIzGvsYkKRrALA76TwiRGPdwIDAQABo4IDNTCCAzEw
# DgYDVR0PAQH/BAQDAgeAMAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYB
# BQUHAwgwggG/BgNVHSAEggG2MIIBsjCCAaEGCWCGSAGG/WwHATCCAZIwKAYIKwYB
# BQUHAgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwggFkBggrBgEFBQcC
# AjCCAVYeggFSAEEAbgB5ACAAdQBzAGUAIABvAGYAIAB0AGgAaQBzACAAQwBlAHIA
# dABpAGYAaQBjAGEAdABlACAAYwBvAG4AcwB0AGkAdAB1AHQAZQBzACAAYQBjAGMA
# ZQBwAHQAYQBuAGMAZQAgAG8AZgAgAHQAaABlACAARABpAGcAaQBDAGUAcgB0ACAA
# QwBQAC8AQwBQAFMAIABhAG4AZAAgAHQAaABlACAAUgBlAGwAeQBpAG4AZwAgAFAA
# YQByAHQAeQAgAEEAZwByAGUAZQBtAGUAbgB0ACAAdwBoAGkAYwBoACAAbABpAG0A
# aQB0ACAAbABpAGEAYgBpAGwAaQB0AHkAIABhAG4AZAAgAGEAcgBlACAAaQBuAGMA
# bwByAHAAbwByAGEAdABlAGQAIABoAGUAcgBlAGkAbgAgAGIAeQAgAHIAZQBmAGUA
# cgBlAG4AYwBlAC4wCwYJYIZIAYb9bAMVMB8GA1UdIwQYMBaAFBUAEisTmLKZB+0e
# 36K+Vw0rZwLNMB0GA1UdDgQWBBRhWk0ktkkynUoqeRqDS/QeicHKfTB9BgNVHR8E
# djB0MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1
# cmVkSURDQS0xLmNybDA4oDagNIYyaHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0QXNzdXJlZElEQ0EtMS5jcmwwdwYIKwYBBQUHAQEEazBpMCQGCCsGAQUF
# BzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQQYIKwYBBQUHMAKGNWh0dHA6
# Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRENBLTEuY3J0
# MA0GCSqGSIb3DQEBBQUAA4IBAQCdJX4bM02yJoFcm4bOIyAPgIfliP//sdRqLDHt
# OhcZcRfNqRu8WhY5AJ3jbITkWkD73gYBjDf6m7GdJH7+IKRXrVu3mrBgJuppVyFd
# NC8fcbCDlBkFazWQEKB7l8f2P+fiEUGmvWLZ8Cc9OB0obzpSCfDscGLTYkuw4HOm
# ksDTjjHYL+NtFxMG7uQDthSr849Dp3GdId0UyhVdkkHa+Q+B0Zl0DSbEDn8btfWg
# 8cZ3BigV6diT5VUW8LsKqxzbXEgnZsijiwoc5ZXarsQuWaBh3drzbaJh6YoLbewS
# GL33VVRAA5Ira8JRwgpIr7DUbuD0FAo6G+OPPcqvao173NhEMIIGzTCCBbWgAwIB
# AgIQBv35A5YDreoACus/J7u6GzANBgkqhkiG9w0BAQUFADBlMQswCQYDVQQGEwJV
# UzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQu
# Y29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMDYx
# MTEwMDAwMDAwWhcNMjExMTEwMDAwMDAwWjBiMQswCQYDVQQGEwJVUzEVMBMGA1UE
# ChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYD
# VQQDExhEaWdpQ2VydCBBc3N1cmVkIElEIENBLTEwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQDogi2Z+crCQpWlgHNAcNKeVlRcqcTSQQaPyTP8TUWRXIGf
# 7Syc+BZZ3561JBXCmLm0d0ncicQK2q/LXmvtrbBxMevPOkAMRk2T7It6NggDqww0
# /hhJgv7HxzFIgHweog+SDlDJxofrNj/YMMP/pvf7os1vcyP+rFYFkPAyIRaJxnCI
# +QWXfaPHQ90C6Ds97bFBo+0/vtuVSMTuHrPyvAwrmdDGXRJCgeGDboJzPyZLFJCu
# WWYKxI2+0s4Grq2Eb0iEm09AufFM8q+Y+/bOQF1c9qjxL6/siSLyaxhlscFzrdfx
# 2M8eCnRcQrhofrfVdwonVnwPYqQ/MhRglf0HBKIJAgMBAAGjggN6MIIDdjAOBgNV
# HQ8BAf8EBAMCAYYwOwYDVR0lBDQwMgYIKwYBBQUHAwEGCCsGAQUFBwMCBggrBgEF
# BQcDAwYIKwYBBQUHAwQGCCsGAQUFBwMIMIIB0gYDVR0gBIIByTCCAcUwggG0Bgpg
# hkgBhv1sAAEEMIIBpDA6BggrBgEFBQcCARYuaHR0cDovL3d3dy5kaWdpY2VydC5j
# b20vc3NsLWNwcy1yZXBvc2l0b3J5Lmh0bTCCAWQGCCsGAQUFBwICMIIBVh6CAVIA
# QQBuAHkAIAB1AHMAZQAgAG8AZgAgAHQAaABpAHMAIABDAGUAcgB0AGkAZgBpAGMA
# YQB0AGUAIABjAG8AbgBzAHQAaQB0AHUAdABlAHMAIABhAGMAYwBlAHAAdABhAG4A
# YwBlACAAbwBmACAAdABoAGUAIABEAGkAZwBpAEMAZQByAHQAIABDAFAALwBDAFAA
# UwAgAGEAbgBkACAAdABoAGUAIABSAGUAbAB5AGkAbgBnACAAUABhAHIAdAB5ACAA
# QQBnAHIAZQBlAG0AZQBuAHQAIAB3AGgAaQBjAGgAIABsAGkAbQBpAHQAIABsAGkA
# YQBiAGkAbABpAHQAeQAgAGEAbgBkACAAYQByAGUAIABpAG4AYwBvAHIAcABvAHIA
# YQB0AGUAZAAgAGgAZQByAGUAaQBuACAAYgB5ACAAcgBlAGYAZQByAGUAbgBjAGUA
# LjALBglghkgBhv1sAxUwEgYDVR0TAQH/BAgwBgEB/wIBADB5BggrBgEFBQcBAQRt
# MGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEF
# BQcwAoY3aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJl
# ZElEUm9vdENBLmNydDCBgQYDVR0fBHoweDA6oDigNoY0aHR0cDovL2NybDMuZGln
# aWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDA6oDigNoY0aHR0
# cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNy
# bDAdBgNVHQ4EFgQUFQASKxOYspkH7R7for5XDStnAs0wHwYDVR0jBBgwFoAUReui
# r/SSy4IxLVGLp6chnfNtyA8wDQYJKoZIhvcNAQEFBQADggEBAEZQPsm3KCSnOB22
# WymvUs9S6TFHq1Zce9UNC0Gz7+x1H3Q48rJcYaKclcNQ5IK5I9G6OoZyrTh4rHVd
# Fxc0ckeFlFbR67s2hHfMJKXzBBlVqefj56tizfuLLZDCwNK1lL1eT7EF0g49GqkU
# W6aGMWKoqDPkmzmnxPXOHXh2lCVz5Cqrz5x2S+1fwksW5EtwTACJHvzFebxMElf+
# X+EevAJdqP77BzhPDcZdkbkPZ0XN1oPt55INjbFpjE/7WeAjD9KqrgB87pxCDs+R
# 1ye3Fu4Pw718CqDuLAhVhSK46xgaTfwqIa1JMYNHlXdx3LEbS0scEJx3FMGdTy9a
# lQgpECYxggQ7MIIENwIBATCBhjByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhE
# aWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgQ29kZSBTaWduaW5nIENBAhAEFyN+d3b/
# SU+2TgBzZeQTMAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAA
# MBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgor
# BgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBQE5+oxTByjQPL/jlMA1HzgW8TgBDAN
# BgkqhkiG9w0BAQEFAASCAQDXWFAjquzwdpMFQYFstYFCYiQG6+cgACqH+U36HvqX
# DoHdroFcvkin1uA90xPlwqFqARr1kZfFuzx4EWCFxnXTnY/3eaNU7yaWa8CLr+K/
# ng7F1//ZpYl0I/QnKjhiOWqtnMVBXoI0chwUdIeX7PZmIIJjKsi7rCrK+x/pfjVP
# Gj/RbdYenkyQvf/sExRy9D2X9r/C2MIwvXKnHXo/KjXWhQbDfZ4vZjFUy2XBDOjx
# BT4k7J56j5gpYYkGs2hAwsCG64AYu7ZMRQtqmWjd6uoVHgm2C6D7bG5zyCB0qT54
# 1jd1REDQ9xax4E9rV6YZXGHtifZ/i+LfBBdOm9M3/iaMoYICDzCCAgsGCSqGSIb3
# DQEJBjGCAfwwggH4AgEBMHYwYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lD
# ZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGln
# aUNlcnQgQXNzdXJlZCBJRCBDQS0xAhADAZoCOv9YsWvW1ermF/BmMAkGBSsOAwIa
# BQCgXTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0y
# MDA4MjcyMjAyMzNaMCMGCSqGSIb3DQEJBDEWBBS3EMhbFunnXsjEAM2cnLDJgK+c
# jzANBgkqhkiG9w0BAQEFAASCAQB5quF6gNF9CrROXr81hwjGWPxKhtVss8+/BkoY
# ZGx0xr7U1Na3L146XmZkJKQd8BumraqQtRJBZr01BAD8wD3dU+/IbpckCpAcdjDr
# jXI58ZKdVZHj07i2wNxIm9VfuPQBfiw0JhRgWkB6/zY4osLLCln2LpYhvFgRZhMp
# lgB8+o+TXbMRUPUZQN0OYau1pgt8kHbC0SQFfeByxc53cNSHZdyPA76Se+weP+mD
# 9n0lL9W0TKvMW4N17aGonuvo3TOHSNxiN07BBgMBLik3jzGtoGVMw3lqMWlpPpE9
# ix07tz1FpU7OlSiAwQ1i0OpsHd7+gD92rvdSBJXoyj/umTru
# SIG # End signature block
