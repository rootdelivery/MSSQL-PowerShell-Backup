BACKUP DATABASE [$(DBNAME)] TO DISK = N'$(BPATH)$(BFILE)' WITH RETAINDAYS = 21, NOFORMAT, NOINIT, NAME = N'$(BNAME)', SKIP, REWIND, NOUNLOAD, COMPRESSION, STATS = 10, CHECKSUM
GO
declare @backupSetId as int
select @backupSetId = position from msdb..backupset where database_name=N'$(DBNAME)' and backup_set_id=(select max(backup_set_id) from msdb..backupset where database_name=N'$(DBNAME)' )
if @backupSetId is null begin raiserror(N'Verify failed. Backup information for database ''$(DBNAME)'' not found.', 16, 1) end
RESTORE VERIFYONLY FROM  DISK = N'$(BPATH)$(BFILE)' WITH  FILE = @backupSetId,  NOUNLOAD,  NOREWIND
