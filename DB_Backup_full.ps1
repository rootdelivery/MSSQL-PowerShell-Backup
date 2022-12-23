# Если в планировщике лезет ошибка Import-Module : The specified module 'SQLASCmdlets' was not loaded because no valid module file was found in any module directory. 
# At C:\Program Files (x86)\Microsoft SQL Server\130\Tools\PowerShell\Modules\SQLPS\SqlPsPostScript.ps1:12 char:1
# Закомментировать эту строку, если модуль не нужен. https://stackoverflow.com/a/48529858

# Планировщик запускает задачу по субботам - доп проверка, костыль, да.
# Воскресенье - оказалось 0
if (( get-date ).DayOfWeek.value__ -ne 0 -and $args[0] -ne '--force') {
    exit
}
if ((Get-Module -ListAvailable | where-object {($_.Name -eq 'SqlServer') -and ($_.Version.Major -gt 20) } |Measure).Count -eq 1){
    # implementation of new sql modules migated into new location
    Import-Module SqlServer -DisableNameChecking -Verbose
}
else{
    # fallback for SQLPS 
    Import-Module SQLPS -DisableNameChecking -Verbose
}

# Write log
$ScriptName = $MyInvocation.MyCommand.Name
$Log = "C:\DWH\DB_Backup_full.log"
$ErrorActionPreference="SilentlyContinue"
Stop-Transcript | out-null
$ErrorActionPreference = "Continue"
Start-Transcript -path $Log
$Error.Clear()

# Start date for error checking
$BDATE = Get-Date

$res = "Successfull"

# Filesize format
Update-TypeData -TypeName System.IO.FileInfo -MemberName FileSize -MemberType ScriptProperty -Value {
     switch($this.length) {
                { $_ -gt 1tb }
                       { "{0:f0} TB" -f ($_ / 1tb) ; break }
                { $_ -gt 1gb }
                       { "{0:f0} GB" -f ($_ / 1gb) ; break }
                { $_ -gt 1mb }
                       { "{0:f0} MB" -f ($_ / 1mb) ; break }
                default
                       { "{0}" -f $_}
              }

} -Force

# PATH one for all
$LPATH = "C:\DWH\backup\DB\Full\"
mkdir "$LPATH" -ErrorAction Ignore
$BPATH = "\\backup31\BackUps\DB\Full\"
mkdir "$BPATH" -ErrorAction Ignore


# meresources
$NOWD = Get-Date -Format yyyy'-'MM'-'dd'_'HHmmss
$DBNAME = "meresources"
$BNAME= "${DBNAME}_Full_$NOWD"
$BFILE= "$BNAME.bak"
$StringArray = "DBNAME=$DBNAME", "BNAME=$BNAME", "BFILE=$BFILE", "BPATH=$LPATH"
#Invoke-Sqlcmd -InputFile .\test.sql -Variable $StringArray
Invoke-Sqlcmd -QueryTimeout 14400 -ServerInstance db21 -InputFile C:\DWH\PWS\backup_DBs\DB_Backup_full.sql -Variable $StringArray -OutputSqlErrors $true

# ReportServer
$NOWD = Get-Date -Format yyyy'-'MM'-'dd'_'HHmmss
$DBNAME = "ReportServer"
$BNAME= "${DBNAME}_Full_$NOWD"
$BFILE= "$BNAME.bak"
$StringArray = "DBNAME=$DBNAME", "BNAME=$BNAME", "BFILE=$BFILE", "BPATH=$LPATH"
Invoke-Sqlcmd -QueryTimeout 14400 -ServerInstance db21 -InputFile C:\DWH\PWS\backup_DBs\DB_Backup_full.sql -Variable $StringArray -OutputSqlErrors $true

# ReportServerTempDB
$NOWD = Get-Date -Format yyyy'-'MM'-'dd'_'HHmmss
$DBNAME = "ReportServerTempDB"
$BNAME= "${DBNAME}_Full_$NOWD"
$BFILE= "$BNAME.bak"
$StringArray = "DBNAME=$DBNAME", "BNAME=$BNAME", "BFILE=$BFILE", "BPATH=$LPATH"
Invoke-Sqlcmd -QueryTimeout 14400 -ServerInstance db21 -InputFile C:\DWH\PWS\backup_DBs\DB_Backup_full.sql -Variable $StringArray -OutputSqlErrors $true

# Fare
$NOWD = Get-Date -Format yyyy'-'MM'-'dd'_'HHmmss
$DBNAME = "Fare"
$BNAME= "${DBNAME}_Full_$NOWD"
$BFILE= "$BNAME.bak"
$StringArray = "DBNAME=$DBNAME", "BNAME=$BNAME", "BFILE=$BFILE", "BPATH=$LPATH"
Invoke-Sqlcmd -QueryTimeout 14400 -ServerInstance db21 -InputFile C:\DWH\PWS\backup_DBs\DB_Backup_full.sql -Variable $StringArray -OutputSqlErrors $true
# Сохраню результат выполнения, чтобы понимать шринкать ли.
$Bres = $?
# Shrink
#if ($Bres) {
#    Invoke-Sqlcmd -QueryTimeout 14400 -ServerInstance db21 -InputFile .\DB_Shrink.sql -Variable $StringArray -OutputSqlErrors $true
#    $Sres = $?
#}

# 21day rotation
$NOW = Get-Date
# Days retention
$DAYS = "21.5"
$TIMETARGET = $NOW.AddDays(-$DAYS)

$FILES = Get-ChildItem $LPATH | where {$_.LastWriteTime -le "$TIMETARGET"}

if ($error.Count -eq 0) {
    foreach ($FILE in $FILES) {
        Write-Host "Deleting file: $FILE"
        # Remove-Item $File.FullName | Out-Null
        Remove-Item $File.FullName -Force -Recurse
    }
}

$FILES = Get-ChildItem $BPATH | where {$_.LastWriteTime -le "$TIMETARGET"}

if ($error.Count -eq 0) {
    foreach ($FILE in $FILES) {
        Write-Host "Deleting file: $FILE"
        # Remove-Item $File.FullName | Out-Null
        Remove-Item $File.FullName -Force -Recurse
    }
}


$LPATHX=$LPATH.Substring(0,$LPATH.Length-1)
xcopy "$LPATHX" "$BPATH" /s /d


$lbackupdir = Get-ChildItem $LPATH | sort LastWriteTime -Descending | Format-Table -Property Name, @{n='FileSize';e={$_.FileSize};a='right'}, LastWriteTime | Out-String
$backupdir = Get-ChildItem $BPATH | sort LastWriteTime -Descending | Format-Table -Property Name, @{n='FileSize';e={$_.FileSize};a='right'}, LastWriteTime | Out-String

# Stop logging
Stop-Transcript

# Check result
if ($error.Count -gt 0) { $res = "FAILED!!!" }

# Email report
$ERR = $error | Out-String
$emailTo = ""
$subject = "backup DBs Full $res"
$body = "Errors count = " + $error.Count.ToString() + "<br>Local copy<pre>" + $lbackupdir + "</pre><br>Remote copy to DC<pre>" + $backupdir + "</pre><br><pre>" + $ERR + "</pre>"

$smtpUsername = ""
$smtpPassword = ""
$credentials = new-object Management.Automation.PSCredential $smtpUsername, ($smtpPassword | ConvertTo-SecureString -AsPlainText -Force)
Send-MailMessage -SmtpServer smtp.gmail.com -Port 587 -UseSsl -Credential $credentials -From $smtpUsername -To $emailTo -Subject $subject -BodyAsHtml -Body $body -Attachments "$Log"

#Send message to Telegram
if ($error.Count -gt 0) {

$token = ""
$chat_id = ""
$errorcountstring = $error.Count.ToString()

$text = "<b>$subject</b>
Errors count = $errorcountstring.
$ERR"

$payload = @{
    "chat_id" = $chat_id;
    "text" = $text;
    "parse_mode" = 'html';
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest `
    -Uri ("https://api.telegram.org/bot{0}/sendMessage" -f $token) `
    -Method Post `
    -ContentType "application/json;charset=utf-8" `
    -Body (ConvertTo-Json -Compress -InputObject $payload)

}



