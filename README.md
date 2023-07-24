# Camera Upload and Backup

This script:
- Creates the appropriate directories in a couple NFS mounted directories on my Ubuntu machine that are mapped to my [Synology]
- Copies all of the contents on the memory card to that directory 
- Creates a tar of that batch of pictures (in case I need to recover the whole batch)
- Uploads both the individual pictures and the tar archive to Amazon S3, which buckets has a lifecycle management rule that transitions it to [Amazon Glacier Deep Archive] after 1 day
- Finally uploads all of the pictures to Google Photos 
