DECLARE @preferredReplica int

SET @preferredReplica = (SELECT [master].sys.fn_hadr_backup_is_preferred_replica('$(DBNAME)'))

IF (@preferredReplica = 1)
BEGIN
    BACKUP LOG [$(DBNAME)] TO  DISK = N'$(BPATH)$(BFILE)' WITH  RETAINDAYS = 21, NOFORMAT, NOINIT,  NAME = N'$(BNAME)', SKIP, REWIND, NOUNLOAD, COMPRESSION,  STATS = 10, CHECKSUM
END
GO
declare @backupSetId as int
select @backupSetId = position from msdb..backupset where database_name=N'$(DBNAME)' and backup_set_id=(select max(backup_set_id) from msdb..backupset where database_name=N'$(DBNAME)' )
if @backupSetId is null begin raiserror(N'Verify failed. Backup information for database ''$(DBNAME)'' not found.', 16, 1) end
RESTORE VERIFYONLY FROM  DISK = N'$(BPATH)$(BFILE)' WITH  FILE = @backupSetId,  NOUNLOAD,  NOREWIND
