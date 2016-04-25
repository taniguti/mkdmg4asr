### mkdmg4asr - Create DiskImage for asr (Apple Software Restore)
___
USAGE::
mkdmg4asr.sh /fullpath/to/srcvolume /fullpath/to/distination [stream]

Source disk must NOT be current start up disk.
If you add 3rd arg, "stream", image will be ready for multicast 
restore via network. Default behavior is NOT for multicast.
