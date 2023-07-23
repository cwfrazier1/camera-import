#!/bin/bash

# Prompt for the camera selection
echo "Select the camera:"
echo "1. D7500"
echo "2. Z5"
read -p "Enter the number for the camera (1 or 2): " camera_choice

# Get the current date
current_date=$(date +'%Y-%m-%d-%s')

mkdir /home/cwfrazier/original-pictures/"$current_date"

# Check camera selection
if [ "$camera_choice" = "1" ]; then
    # Move pictures from D7500 to the current date directory
    mv /media/cwfrazier/NIKON\ D7500/* /home/cwfrazier/original-pictures/"$current_date"/
elif [ "$camera_choice" = "2" ]; then
    mv /media/cwfrazier/NIKON\ Z\ 5/* /home/cwfrazier/original-pictures/"$current_date"/
else
    echo "Invalid camera selection. Please enter either '1' for D7500 or '2' for Z5."
    exit 1
fi

# Create directories with the current date
mkdir -p /home/cwfrazier/original-pictures/"$current_date"

# Create a tar archive with the current date directory
tar cf /home/cwfrazier/original-pictures-archive/"$current_date".tar.gz /home/cwfrazier/original-pictures/"$current_date"/

# Copy files to S3
rclone copy /home/cwfrazier/original-pictures/"$current_date" s3:cwfrazier-original-pictures/"$current_date" --verbose --ignore-existing
rclone copy /home/cwfrazier/original-pictures-archive/"$current_date".tar.gz s3:cwfrazier-original-pictures/original-pictures-archive --verbose --ignore-existing
rclone mkdir gp:album/"$current_date"
rclone copy /home/cwfrazier/original-pictures/"$current_date" gp:album/"$current_date" --verbose --ignore-existing
