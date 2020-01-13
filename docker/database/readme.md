# Script to build a database docker image

To build the image run:

`docker build -t transport_data_gouv_dev_database --build-arg BACKUP_PATH=<path_to_the_backup_file> .`

Note: backup file needs to be in the directory.

If you want to push it to dockerhub (change the destination image name if needed):

`docker login`

`docker tag transport_data_gouv_dev_database antoinede/transport_data_gouv_dev_database:latest`

`docker push antoinede/transport_data_gouv_dev_database:latest`