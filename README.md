# check_glusterfs
Forked from Mark Ruys' check_glusterfs from exchange.nagios 


Changes:

Version 1.1:
Added support for TB sized drives by emitor@gmail.com

Version 1.2:
The script now autodiscovers the numbers of bricks and replicas
The script now outputs the correct size when more than 1 x 2 bricks exists

Version 1.3:
The script now alarms on bad volume status
