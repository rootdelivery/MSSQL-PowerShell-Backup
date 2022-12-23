# Если в планировщике лезет ошибка Import-Module : The specified module 'SQLASCmdlets' was not loaded because no valid module file was found in any module directory. 
# At C:\Program Files (x86)\Microsoft SQL Server\130\Tools\PowerShell\Modules\SQLPS\SqlPsPostScript.ps1:12 char:1
# Закомментировать эту строку, если модуль не нужен. https://stackoverflow.com/a/48529858
# import modules 
if ((Get-Module -ListAvailable | where-object {($_.Name -eq 'SqlServer') -and ($_.Version.Major -gt 20) } |Measure).Count -eq 1){
    # implementation of new sql modules migated into new location
    Import-Module SqlServer -DisableNameChecking -Verbose
}
else{
    # fallback for SQLPS 
    Import-Module SQLPS -DisableNameChecking -Verbose
}
# Write log
#Set-PSDebug -Trace 2
$ScriptName = $MyInvocation.MyCommand.Name
$Log = "C:\DWH\DB_Backup_log.log"
$ErrorActionPreference="SilentlyContinue"
Stop-Transcript | out-null
$ErrorActionPreference = "Continue"
Start-Transcript -path $Log
$Error.Clear()

# Date for log
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

# First copy to locan then remote
$LPATH = "C:\DWH\backup\DB\Log\"
mkdir "$LPATH" -ErrorAction Ignore
$BPATH = "\\backup31\BackUps\DB\Fare\Trn_log\"

# Fare
$NOWD = Get-Date -Format yyyy'-'MM'-'dd'_'HHmmss
$DBNAME = "Fare"
$BNAME= "${DBNAME}_$NOWD"
$BFILE= "$BNAME.trn"
$StringArray = "DBNAME=$DBNAME", "BNAME=$BNAME", "BFILE=$BFILE", "BPATH=$LPATH"
# Request timeout 55 minutes to catch every hour
Invoke-Sqlcmd -QueryTimeout 3300 -ServerInstance db21 -InputFile F:\PWS\backup_DBs\DB_Backup_log.sql -Variable $StringArray -OutputSqlErrors $true

# Copy rotation 22 days, enough for the oldest diff and full
$NOW = Get-Date
# Days retention
$DAYS = "22.5"
$TIMETARGET = $NOW.AddDays(-$DAYS)

# Local
$FILES = Get-ChildItem $LPATH | where {$_.LastWriteTime -le "$TIMETARGET"}

if ($error.Count -eq 0) {
    foreach ($FILE in $FILES) {
        Write-Host "Deleting file: $FILE"
        # Remove-Item $File.FullName | Out-Null
        Remove-Item $File.FullName -Force -Recurse
    }
}

# Copy to remote only new
#Copy-Item -Path "$LPATH\*" -Destination "$BPATH\" -recurse -Force -Verbose
# I remove the backlash, otherwise xcopy does not work
$LPATHX=$LPATH.Substring(0,$LPATH.Length-1)
xcopy "$LPATHX" "$BPATH" /s /d

# Remote
$FILES = Get-ChildItem $BPATH | where {$_.LastWriteTime -le "$TIMETARGET"}

if ($error.Count -eq 0) {
    foreach ($FILE in $FILES) {
        Write-Host "Deleting file: $FILE"
        # Remove-Item $File.FullName | Out-Null
        Remove-Item $File.FullName -Force -Recurse
    }
}

$lbackupdir = Get-ChildItem $LPATH | sort LastWriteTime -Descending | Format-Table -Property Name, @{n='FileSize';e={$_.FileSize};a='right'}, LastWriteTime | Out-String
$backupdir = Get-ChildItem $BPATH | sort LastWriteTime -Descending | Format-Table -Property Name, @{n='FileSize';e={$_.FileSize};a='right'}, LastWriteTime | Out-String

# Stop log
Stop-Transcript

# Check result
if ($error.Count -gt 0) { $res = "FAILED!!!" }

# Send email
$ERR = $error | Out-String

$EmailFrom = ""
$EmailTo = ""
$Subject = "backup DBs Trn Log $res"
$Body = "Errors count = " + $error.Count.ToString() + "<br>Local copy<pre>" + $lbackupdir + "</pre><br>Remote copy to DC<pre>" + $backupdir + "</pre><br><pre>" + $ERR + "</pre>"
$SMTPServer = ""
$SMTPClient = New-Object Net.Mail.SmtpClient($SmtpServer, 587)
$SMTPClient.EnableSsl = $true
$SMTPClient.Credentials = New-Object System.Net.NetworkCredential("", "");
$SMTPClient.Send($EmailFrom, $EmailTo, $Subject, $Body)

#!!!!!!!!!!!!!!!!!!!!!!!!!!
# Send message via Telegram_vb
#!!!!!!!!!!!!!!!!!!!!!!!!!!

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
#!!!!!!!!!!!!!!!!!!!!!!!!!!
