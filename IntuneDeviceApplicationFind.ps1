<#PSScriptInfo

.VERSION 1.1

.GUID aa46f8a4-3d0f-4eda-b157-7e99eb5f4057

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
Update: 10/18/2021 Get-IntuneManagedDevice | Get-MSGraphAllPages stopped working so change to pagination
update: 12/2/2021 changed to filter as MS has made a change in API
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
  $getalldevices = Get-IntuneManagedDevice -Filter "managementagent eq 'mdm'" | Get-MSGraphAllPages 
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
# MIIZiQYJKoZIhvcNAQcCoIIZejCCGXYCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU9PVKIwraSWAN70oEQK0j7FJV
# 31igghSXMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
# AQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFz
# c3VyZWQgSUQgVGltZXN0YW1waW5nIENBMB4XDTIxMDEwMTAwMDAwMFoXDTMxMDEw
# NjAwMDAwMFowSDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMu
# MSAwHgYDVQQDExdEaWdpQ2VydCBUaW1lc3RhbXAgMjAyMTCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBAMLmYYRnxYr1DQikRcpja1HXOhFCvQp1dU2UtAxQ
# tSYQ/h3Ib5FrDJbnGlxI70Tlv5thzRWRYlq4/2cLnGP9NmqB+in43Stwhd4CGPN4
# bbx9+cdtCT2+anaH6Yq9+IRdHnbJ5MZ2djpT0dHTWjaPxqPhLxs6t2HWc+xObTOK
# fF1FLUuxUOZBOjdWhtyTI433UCXoZObd048vV7WHIOsOjizVI9r0TXhG4wODMSlK
# XAwxikqMiMX3MFr5FK8VX2xDSQn9JiNT9o1j6BqrW7EdMMKbaYK02/xWVLwfoYer
# vnpbCiAvSwnJlaeNsvrWY4tOpXIc7p96AXP4Gdb+DUmEvQECAwEAAaOCAbgwggG0
# MA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsG
# AQUFBwMIMEEGA1UdIAQ6MDgwNgYJYIZIAYb9bAcBMCkwJwYIKwYBBQUHAgEWG2h0
# dHA6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAfBgNVHSMEGDAWgBT0tuEgHf4prtLk
# YaWyoiWyyBc1bjAdBgNVHQ4EFgQUNkSGjqS6sGa+vCgtHUQ23eNqerwwcQYDVR0f
# BGowaDAyoDCgLoYsaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJl
# ZC10cy5jcmwwMqAwoC6GLGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFz
# c3VyZWQtdHMuY3JsMIGFBggrBgEFBQcBAQR5MHcwJAYIKwYBBQUHMAGGGGh0dHA6
# Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBPBggrBgEFBQcwAoZDaHR0cDovL2NhY2VydHMu
# ZGlnaWNlcnQuY29tL0RpZ2lDZXJ0U0hBMkFzc3VyZWRJRFRpbWVzdGFtcGluZ0NB
# LmNydDANBgkqhkiG9w0BAQsFAAOCAQEASBzctemaI7znGucgDo5nRv1CclF0CiNH
# o6uS0iXEcFm+FKDlJ4GlTRQVGQd58NEEw4bZO73+RAJmTe1ppA/2uHDPYuj1UUp4
# eTZ6J7fz51Kfk6ftQ55757TdQSKJ+4eiRgNO/PT+t2R3Y18jUmmDgvoaU+2QzI2h
# F3MN9PNlOXBL85zWenvaDLw9MtAby/Vh/HUIAHa8gQ74wOFcz8QRcucbZEnYIpp1
# FUL1LTI4gdr0YKK6tFL7XOBhJCVPst/JKahzQ1HavWPWH1ub9y4bTxMd90oNcX6X
# t/Q/hOvB46NJofrOp79Wz7pZdmGJX36ntI5nePk2mOHLKNpbh6aKLzCCBSgwggQQ
# oAMCAQICEAQXI353dv9JT7ZOAHNl5BMwDQYJKoZIhvcNAQELBQAwcjELMAkGA1UE
# BhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2lj
# ZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIENvZGUg
# U2lnbmluZyBDQTAeFw0yMDA3MDgwMDAwMDBaFw0yMzA3MTMxMjAwMDBaMGUxCzAJ
# BgNVBAYTAkNBMRAwDgYDVQQIEwdPbnRhcmlvMRQwEgYDVQQHEwtNaXNzaXNzYXVn
# YTEWMBQGA1UEChMNVmlrYXMgU3VraGlqYTEWMBQGA1UEAxMNVmlrYXMgU3VraGlq
# YTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOErfHfQ6pn1mETF7PWp
# qbB4eqlRuJFRGgdQAPRkvYrVRlILZM/tfFuZkr6cplV+3u/eRxlAqkeRnzbiRK+o
# wmi12Znw5otzPJuZRSb6gm1dSGbZTfay2JXCglc8L0ZtsnLXHRUi8wdbKSpv9eYI
# 8reeOiXVbUHubs73+EXH+UlDiCMs7LpwPyVjyt5o0JMdBcoHjdRIhx1UKEBCeWy0
# wziqDY94pwCuzeDQrsXt/UfMWzk11H2Zuf2XYPDIy0F7NsyhDx7bMifM0QFWC0C1
# Iinbh8MGUue18mjllTpYcSwzNUF11d9VzRGwhZ8AU2bet8TIAekt/4P5aWMdT9ta
# K1ECAwEAAaOCAcUwggHBMB8GA1UdIwQYMBaAFFrEuXsqCqOl6nEDwGD5LfZldQ5Y
# MB0GA1UdDgQWBBTLtvyqDKFiIsTfPo2xPDoKTFK+oDAOBgNVHQ8BAf8EBAMCB4Aw
# EwYDVR0lBAwwCgYIKwYBBQUHAwMwdwYDVR0fBHAwbjA1oDOgMYYvaHR0cDovL2Ny
# bDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJlZC1jcy1nMS5jcmwwNaAzoDGGL2h0
# dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQtY3MtZzEuY3JsMEwG
# A1UdIARFMEMwNwYJYIZIAYb9bAMBMCowKAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3
# LmRpZ2ljZXJ0LmNvbS9DUFMwCAYGZ4EMAQQBMIGEBggrBgEFBQcBAQR4MHYwJAYI
# KwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBOBggrBgEFBQcwAoZC
# aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0U0hBMkFzc3VyZWRJ
# RENvZGVTaWduaW5nQ0EuY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQAD
# ggEBAE/k53BL9tN6EKPruAwxzJ+qZE3J88f1t5a8LIx1fgtEXBL00NJJqaoKkNVz
# t7RoT4d6yQHSFC/TNYFBLUnYOF3myRuO9L2ty05toSzGxHKUmK5E3ablxM0PQTuC
# GgHVkV85/1VlXkUu/UQUXuESsvEm70OUW36AlI2dMugHRrnwYSrEqjBIk8imUV0X
# G2sNd/AJFoo0PCfRpNVABjxfJeZmKOdKeYBYZpXqSmKdJ7TQSRiRP50XDD1egWOW
# bfL6qZyxoa3XHmZF18APCRbEuWdHZEBr4QfMfI1/sUDFMlOf4hU6tTav9uyxSo+7
# 8QyfP5YBCemOOrKeKwY4Yv0PxRgwggUwMIIEGKADAgECAhAECRgbX9W7ZnVTQ7Vv
# lVAIMA0GCSqGSIb3DQEBCwUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdp
# Q2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0Rp
# Z2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0xMzEwMjIxMjAwMDBaFw0yODEw
# MjIxMjAwMDBaMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMx
# GTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNI
# QTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQD407Mcfw4Rr2d3B9MLMUkZz9D7RZmxOttE9X/lqJ3bMtdx
# 6nadBS63j/qSQ8Cl+YnUNxnXtqrwnIal2CWsDnkoOn7p0WfTxvspJ8fTeyOU5JEj
# lpB3gvmhhCNmElQzUHSxKCa7JGnCwlLyFGeKiUXULaGj6YgsIJWuHEqHCN8M9eJN
# YBi+qsSyrnAxZjNxPqxwoqvOf+l8y5Kh5TsxHM/q8grkV7tKtel05iv+bMt+dDk2
# DZDv5LVOpKnqagqrhPOsZ061xPeM0SAlI+sIZD5SlsHyDxL0xY4PwaLoLFH3c7y9
# hbFig3NBggfkOItqcyDQD2RzPJ6fpjOp/RnfJZPRAgMBAAGjggHNMIIByTASBgNV
# HRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggrBgEF
# BQcDAzB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRp
# Z2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCBgQYDVR0fBHoweDA6oDig
# NoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9v
# dENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# QXNzdXJlZElEUm9vdENBLmNybDBPBgNVHSAESDBGMDgGCmCGSAGG/WwAAgQwKjAo
# BggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAKBghghkgB
# hv1sAzAdBgNVHQ4EFgQUWsS5eyoKo6XqcQPAYPkt9mV1DlgwHwYDVR0jBBgwFoAU
# Reuir/SSy4IxLVGLp6chnfNtyA8wDQYJKoZIhvcNAQELBQADggEBAD7sDVoks/Mi
# 0RXILHwlKXaoHV0cLToaxO8wYdd+C2D9wz0PxK+L/e8q3yBVN7Dh9tGSdQ9RtG6l
# jlriXiSBThCk7j9xjmMOE0ut119EefM2FAaK95xGTlz/kLEbBw6RFfu6r7VRwo0k
# riTGxycqoSkoGjpxKAI8LpGjwCUR4pwUR6F6aGivm6dcIFzZcbEMj7uo+MUSaJ/P
# QMtARKUT8OZkDCUIQjKyNookAv4vcn4c10lFluhZHen6dGRrsutmQ9qzsIzV6Q3d
# 9gEgzpkxYz0IGhizgZtPxpMQBvwHgfqL2vmCSfdibqFT+hKUGIUukpHqaGxEMrJm
# oecYpJpkUe8wggUxMIIEGaADAgECAhAKoSXW1jIbfkHkBdo2l8IVMA0GCSqGSIb3
# DQEBCwUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0RpZ2lDZXJ0IEFzc3Vy
# ZWQgSUQgUm9vdCBDQTAeFw0xNjAxMDcxMjAwMDBaFw0zMTAxMDcxMjAwMDBaMHIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJ
# RCBUaW1lc3RhbXBpbmcgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC90DLuS82Pf92puoKZxTlUKFe2I0rEDgdFM1EQfdD5fU1ofue2oPSNs4jkl79j
# IZCYvxO8V9PD4X4I1moUADj3Lh477sym9jJZ/l9lP+Cb6+NGRwYaVX4LJ37AovWg
# 4N4iPw7/fpX786O6Ij4YrBHk8JkDbTuFfAnT7l3ImgtU46gJcWvgzyIQD3XPcXJO
# Cq3fQDpct1HhoXkUxk0kIzBdvOw8YGqsLwfM/fDqR9mIUF79Zm5WYScpiYRR5oLn
# RlD9lCosp+R1PrqYD4R/nzEU1q3V8mTLex4F0IQZchfxFwbvPc3WTe8GQv2iUypP
# hR3EHTyvz9qsEPXdrKzpVv+TAgMBAAGjggHOMIIByjAdBgNVHQ4EFgQU9LbhIB3+
# Ka7S5GGlsqIlssgXNW4wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8w
# EgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYI
# KwYBBQUHAwgweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2Nz
# cC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwgYEGA1UdHwR6MHgw
# OqA4oDaGNGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJ
# RFJvb3RDQS5jcmwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdp
# Q2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwUAYDVR0gBEkwRzA4BgpghkgBhv1sAAIE
# MCowKAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwCwYJ
# YIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4IBAQBxlRLpUYdWac3v3dp8qmN6s3jP
# BjdAhO9LhL/KzwMC/cWnww4gQiyvd/MrHwwhWiq3BTQdaq6Z+CeiZr8JqmDfdqQ6
# kw/4stHYfBli6F6CJR7Euhx7LCHi1lssFDVDBGiy23UC4HLHmNY8ZOUfSBAYX4k4
# YU1iRiSHY4yRUiyvKYnleB/WCxSlgNcSR3CzddWThZN+tpJn+1Nhiaj1a5bA9Fhp
# DXzIAbG5KHW3mWOFIoxhynmUfln8jA/jb7UBJrZspe6HUSHkWGCbugwtK22ixH67
# xCUrRwIIfEmuE7bhfEJCKMYYVs9BNLZmXbZ0e/VWMyIvIjayS6JKldj1po5SMYIE
# XDCCBFgCAQEwgYYwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IElu
# YzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQg
# U0hBMiBBc3N1cmVkIElEIENvZGUgU2lnbmluZyBDQQIQBBcjfnd2/0lPtk4Ac2Xk
# EzAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG
# 9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIB
# FTAjBgkqhkiG9w0BCQQxFgQUSz8E0rFwdc472M3+O8kRHYDPklgwDQYJKoZIhvcN
# AQEBBQAEggEANkVGu+EQmAz0iElPM3hkCS+jj27o+Oinlsy8aAlR3iULznjew3kR
# plkLoSuUVjj9T/XTxtdmWiyPBVkLrtNBtPGS2mXksekLKteayaXhljcgqFAoioyQ
# x/5eLcx66znRXPCHBX5pSs8zAewUTSmqpA4108L6YCqFYAt95dRCubaaUSryZaKB
# 5eXPW6iaKn+MLLCqymyKQ/cqnBCivLSYm8D+1vR58aOCsucqoUgF9x41t6sSCe0r
# UiK0qBuimgwliyTybQrS8hNuyPTIb7EpPlT2+Q86yjGYTLiVr5bIJp2GsqP5wFcy
# gHzi+iaFY7HPd4QxF9JWXp5STNCXAjFDOKGCAjAwggIsBgkqhkiG9w0BCQYxggId
# MIICGQIBATCBhjByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5j
# MRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBT
# SEEyIEFzc3VyZWQgSUQgVGltZXN0YW1waW5nIENBAhANQkrgvjqI/2BAIc4UAPDd
# MA0GCWCGSAFlAwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkq
# hkiG9w0BCQUxDxcNMjExMjAyMTQwMTM3WjAvBgkqhkiG9w0BCQQxIgQgFZstGwfv
# SjgWe+yLJyqxXPamEByATSVcBZzUwHJtAnQwDQYJKoZIhvcNAQEBBQAEggEAtQ+X
# sw7oZtOYnP0hiGvF04AyWSZ8XWjIrm1s0gFhPiAMp94g9WkbWBXEA29cptcmR6B5
# 0rENaLe/xWWx2o6+sDVp9+zwaI9hafUlovRFdznEyEA/zPuZaqWVSNNm+RFHQqDg
# wxEWq5J8FHiDoVPHL+Bm0CM6R2qaXe5/6QotoKP77N6o/E6DnGm6W2T4msr4jnZ4
# 3ZUrsrY+HftUOLRmfFTu/pxdwW2DlDzjl3ezTC5pYGGBI0EHu0xFVNgauEgWCrU3
# K9sP/LwdenJ+wxvWelgm0mcTGi82GWrtDGrhg6khuPJiUPjkqCqLebd4UJ4PKMUa
# Vl5ET/IcQoUXyhQiag==
# SIG # End signature block
