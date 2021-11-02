alter table workflow
    add column tasks text not null comment '任务定义';

alter table workflow
    add column options text not null comment '默认参数（继承自  rackhd）';

alter table task
    add column graph_objects text not null comment 'taskgraph 实例';
-- refactor bare_metal
alter table bare_metal modify column hostname varchar (50) default '' comment 'hostanme';
alter table bare_metal modify column cpu_type varchar (50) default '' comment 'cpu type';
alter table bare_metal modify column cpu_fre varchar (50) default '' comment 'cpu frequency';
alter table bare_metal modify column core int (8) default 1 comment 'cpu core';
alter table bare_metal modify column thread int (8) default 1 comment 'cpu thread num';
alter table bare_metal modify column power varchar (50) default '' comment 'power status';
alter table bare_metal modify column rule_id varchar (64) default '' comment 'bare_metal_rule id';
alter table bare_metal
    add column pxe_mac varchar(50) default '' comment 'pxe mac address';
-- 初始化 pxe mac 地址
update bare_metal
set pxe_mac = (select mac from network_card where network_card.bare_metal_id = bare_metal.id and pxe = '1');

insert into workflow
values (uuid(),
        'system',
        'Graph.rancherDiscovery',
        'PXE 发现搜集硬件信息',
        'POST_DISCOVERY_WORKFLOW_START',
        '[]',
        'false',
        '{}',
        'enable',
        now(), '', '');

insert into profile
values (uuid(), 'linux.ipxe',
        'kernel <%=kernelUri%>\ninitrd <%=initrdUri%>\nimgargs <%=kernelFile%> initrd=<%=initrdFile%> auto=true SYSLOGSERVER=<%=server%> API_CB=<%=server%>:<%=port%> BASEFS=<%=basefsUri%> OVERLAYFS=<%=overlayfsUri%> BOOTIF=01-<%=macaddress%> console=tty0 console=<%=comport%>,115200n8 <%=kargs%>\nboot || prompt --key 0x197e --timeout 2000 Press F12 to investigate || exit shell\n',
        'system', 1629698788504, 1629698788504);

insert into profile
values (uuid(), 'redirect.ipxe',
        'set i:int8 0\n\n:loop\nset CurrentIp $\{net$\{i\}/ip\}\nisset $\{CurrentIp\} || goto noipqueryset\nset CurrentIpQuery ips=$\{CurrentIp\}\ngoto ipquerysetdone\n:noipqueryset\nset CurrentIpQuery ips=\n:ipquerysetdone\n\nset CurrentMac $\{net$\{i\}/mac:hex\}\nisset $\{CurrentMac\} || goto done\nset CurrentMacQuery macs=$\{CurrentMac\}\n\niseq $\{i\} 0 || goto notnic0queryset\nset IpsQuery $\{CurrentIpQuery\}\nset MacsQuery $\{CurrentMacQuery\}\ngoto querysetdone\n\n:notnic0queryset\nset IpsQuery $\{IpsQuery\}&$\{CurrentIpQuery\}\nset MacsQuery $\{MacsQuery\}&$\{CurrentMacQuery\}\n:querysetdone\n\necho RackShift: NIC$\{i\} MAC: $\{CurrentMac\}\necho RackShift: NIC$\{i\} IP: $\{CurrentIp\}\n\ninc i\niseq $\{i\} 100 || goto loop\n:done\n\n# Profile request retries\nset getProfileAttempt:int8 0\nset getProfileAttemptMax:int8 5\nset getProfileRetryDelay:int8 3\n\ngoto getProfile\n\n:getProfileRetry\ninc getProfileAttempt\niseq $\{getProfileAttempt\} $\{getProfileAttemptMax\} || goto getProfileRetryContinue\n\necho Exceeded max retries chainloading boot profile\necho Exiting in $\{rebootInterval\} seconds...\n# rebootInterval defined in boilerplate.ipxe\nsleep $\{rebootInterval\}\ngoto complete\n\n:getProfileRetryContinue\necho Failed to download profile, retrying in $\{getProfileRetryDelay\} seconds\nsleep $\{getProfileRetryDelay\}\n\n:getProfile\necho RackShift: Chainloading next profile\nchain http://<%=server%>:<%=port%>/api/current/profiles?$\{MacsQuery\}&$\{IpsQuery\} || goto getProfileRetry\n\n:complete\nexit\n',
        'system', 1629698788504, 1629698788504);

insert into profile
values (uuid(), 'rancherOS.ipxe',
        '# Copyright 2018, Dell EMC, Inc.\nkernel <%=kernelUri%>\ninitrd <%=initrdUri%>\nimgargs <%=kernelFile%> initrd=<%=initrdFile%> console=tty0 netconsole=+@/,514@<%=server%>/ rancher.password=monorail rancher.cloud_init.datasources=[\'url:http://<%=server%>:<%=port%>/api/current/templates/cloud-config.yaml?nodeId=<%=nodeId%>\']\nboot || prompt --key 0x197e --timeout 2000 Press F12 to investigate || exit shell',
        'system', 1629698788504, 1629698788504);


insert into template
values (uuid(), 'cloud-config.yaml',
        '#cloud-config\n# Copyright 2021, FIT2CLOUD\nwrite_files:\n  - path: /etc/rc.local\n    permissions: \"0755\"\n    owner: root\n    content: |\n      #!/bin/bash\n      modprobe ipmi_devintf\n      modprobe ipmi_si\n      wget -O /tmp/micro.tar.xz <%= dockerUri %>\n      while [ $(docker images | grep -c micro) == \"0\" ]; do\n         xz -cd /tmp/micro.tar.xz | docker load\n      done\n      # Run the script in background to enable sshd,\n      # because sshd is enabled after /etc/rc.local is finished.\n      /etc/rackhd-micro.sh &\n\n  - path: /etc/rackhd-micro.sh\n    permissions: \"0755\"\n    owner: root\n    content: |\n      #!/bin/bash\n      wait-for-docker\n      docker run  \\\n          -e SERVER=\' <%= server %>\' \\\n          -e PORT=\'<%= port %>\' \\\n          -e MAC=\'<%= macaddress %>\' \\\n          --privileged --net=host -v=/dev:/dev rackhd/micro\n      case $? in\n        1 )\n            echo 1 | sudo tee /proc/sys/kernel/sysrq\n            echo b | sudo tee /proc/sysrq-trigger\n            ;;\n        2 )\n            ipmitool -I open chassis power cycle ;;\n        127 )\n            exit 0 ;;\n        * )\n            echo 1 | sudo tee /proc/sys/kernel/sysrq\n            echo b | sudo tee /proc/sysrq-trigger\n            ;;\n      esac\n',
        'system', 1629698788504, 1629698788504);


insert into template
values (uuid(), 'bootstrap.js',
        '// Copyright 2021, FIT2CLOUD\n\n\"use strict\";\n\nvar http = require(''http''),\n    url = require(''url''),\n    fs = require(''fs''),\n    path = require(''path''),\n    childProcess = require(''child_process''),\n    exec = childProcess.exec,\n    server = ''<%=server%>'',\n    port = ''<%=port%>'',\n    tasksPath = ''/api/current/tasks/<%=identifier%>'',\n    // Set the buffer size to ~5MB to accept all output in flashing bios\n    // Otherwise the process will be killed if exceeds the buffer size\n    MAX_BUFFER = 5000 * 1024,\n    MAX_RETRY_TIMEOUT = 60 * 1000;\n/**\n * Synchronous each loop from caolan/async.\n * @private\n * @param arr\n * @param iterator\n * @param callback\n * @returns \{*|Function\}\n */\nfunction eachSeries(arr, iterator, callback) \{\n    callback = callback || function () \{\};\n\n    if (!arr.length) \{\n        return callback();\n    \}\n\n    var completed = 0,\n        iterate = function () \{\n            iterator(arr[completed], function (err) \{\n                if (err) \{\n                    callback(err);\n                    callback = function () \{\};\n                \} else \{\n                    completed += 1;\n                    if (completed >= arr.length) \{\n                        callback();\n                    \} else \{\n                        iterate();\n                    \}\n                \}\n            \});\n        \};\n\n    iterate();\n\}\n\n/**\n * Update Tasks - Takes the data from task execution and posts it back to the\n * API server.\n * @private\n * @param data\n * @param timeout\n */\nfunction updateTasks(data, timeout, retry, retries) \{\n\n    var request = http.request(\{\n        hostname: server,\n        port: port,\n        path: tasksPath,\n        method: ''POST'',\n        headers: \{\n            ''Content-Type'': ''application/json''\n        \}\n    \}, function (res) \{\n        res.on(''data'', function () \{\n            // no-op to end the async call\n        \});\n\n        res.on(''end'', function () \{\n            if (timeout && data.exit === undefined) \{\n                console.log(\"Sleeping \" + timeout + \" for Task Execution...\");\n\n                setTimeout(function () \{\n                    getTasks(timeout);\n                \}, timeout);\n            \} else \{\n                console.log(\"Task Execution Complete\");\n                process.exit(data.exit.code || data.exit || 0);\n            \}\n        \});\n    \}).on(''error'', function (err) \{\n            console.log(\"Update Tasks Error: \" + err);\n            if (retries === undefined)\{\n                retries = 1;\n            \}else \{\n                retries = retries + 1;\n            \}\n            console.log(\"Retrying Update Tasks Attempt #\" + retries);\n\n            setTimeout(function () \{\n                updateTasks(data, timeout, retry, retries);\n            \}, Math.min(timeout * retries, MAX_RETRY_TIMEOUT));\n        \});\n\n    // Call error.toString() on certain errors so when it is JSON.stringified\n    // it doesn''t end up as ''\{\}'' before we send it back to the server.\n    data.tasks.forEach(function(task) \{\n        if (task.error && !task.error.code) \{\n            task.error = task.error.toString();\n        \}\n    \});\n\n    request.write(JSON.stringify(data));\n    request.write(\"\\n\");\n    request.end();\n\}\n\n/**\n * Execute Tasks - Tasks the data from get tasks and executes each task serially\n * @private\n * @param data\n * @param timeout\n */\nfunction executeTasks(data, timeout) \{\n    var handleExecResult = function(_task, _done, error, stdout, stderr) \{\n        _task.stdout = stdout;\n        _task.stderr = stderr;\n        _task.error = error;\n\n        console.log(_task.stdout);\n        console.log(_task.stderr);\n\n        if (_task.error !== null) \{\n            console.log(\"_task Error (\" + _task.error.code + \"): \" +\n                        _task.stdout + \"\\n\" +\n                        _task.stderr + \"\\n\" +\n                        _task.error.toString());\n            console.log(\"ACCEPTED RESPONSES \" + _task.acceptedResponseCodes);\n            if (checkValidAcceptCode(_task.acceptedResponseCodes) &&\n                _task.acceptedResponseCodes.indexOf(_task.error.code) >= 0) \{\n\n                console.log(\"_task \" + _task.cmd + \" error code \" + _task.error.code +\n                   \" is acceptable, continuing...\");\n                _done();\n            \} else \{\n                _done(error);\n            \}\n        \} else \{\n            _done();\n        \}\n    \};\n\n    eachSeries(data.tasks, function (task, done) \{\n        if (task.downloadUrl) \{\n            getFile(task.downloadUrl, function(error) \{\n                if (error) \{\n                    handleExecResult(task, done, error);\n                \} else \{\n                    console.log(task.cmd);\n                    exec(task.cmd, \{ maxBuffer: MAX_BUFFER \}, function(error, stdout, stderr) \{\n                        handleExecResult(task, done, error, stdout, stderr);\n                    \});\n                \}\n            \});\n        \} else \{\n            console.log(task.cmd);\n            exec(task.cmd, \{ maxBuffer: MAX_BUFFER \}, function (error, stdout, stderr) \{\n                if (error) \{\n                    handleExecResult(task, done, error);\n                \} else \{\n                    handleExecResult(task, done, error, stdout, stderr, done);\n                \}\n            \});\n        \}\n    \}, function () \{\n        updateTasks(data, timeout);\n    \});\n\}\n\n/**\n * Get Tasks - Retrieves a task list from the API server.\n * @private\n * @param timeout\n */\nfunction getTasks(timeout) \{\n    http.request(\{\n        hostname: server,\n        port: port,\n        path: tasksPath,\n        method: ''GET''\n    \}, function (res) \{\n        var data = \"\";\n\n        res.on(''data'', function (chunk) \{\n            data += chunk;\n        \});\n\n        res.on(''end'', function () \{\n            try \{\n                executeTasks(JSON.parse(data), timeout);\n            \} catch (error) \{\n                // 404 error doesn''t run through the on error handler.\n                console.log(\"No tasks available.\");\n\n                if (timeout) \{\n                    console.log(\"Sleeping \" + timeout +\n                                    \" for Task Execution...\");\n\n                    setTimeout(function () \{\n                        getTasks(timeout);\n                    \}, timeout);\n                \} else \{\n                    console.log(\"Task Execution Complete\");\n                \}\n            \}\n        \});\n    \}).on(''error'', function (err) \{\n        console.log(\"Get Tasks Error: \" + err);\n\n        if (timeout) \{\n            console.log(\"Sleeping \" + timeout + \" for Task Execution...\");\n\n            setTimeout(function () \{\n                getTasks(timeout);\n            \}, timeout);\n        \} else \{\n            console.log(\"Task Execution Complete\");\n        \}\n    \}).end();\n\}\n\n/**\n * Get Tasks - Retrieves a script from the API server (via several potential\n *             API routes such as /files, /templates, or static files)\n * @private\n * @param downloadUrl\n * @param cb\n */\nfunction getFile(downloadUrl, cb) \{\n    var urlObj = url.parse(downloadUrl);\n    http.request(urlObj, function (res) \{\n        var filename = path.basename(urlObj.pathname);\n        var stream = fs.createWriteStream(filename);\n\n        res.on(''end'', function () \{\n            stream.end(function() \{\n                // Close to a noop on windows, just flips the R/W bit\n                fs.chmod(filename, \"0555\", function(error) \{\n                    if (error) \{\n                        cb(error);\n                    \} else \{\n                        cb(null);\n                    \}\n                \});\n            \});\n        \});\n\n        res.on(''error'', function (error) \{\n            stream.end();\n            cb(error);\n        \});\n\n        res.pipe(stream);\n\n    \}).on(''error'', function (error) \{\n        cb(error);\n    \}).end();\n\}\n\n/**\n * Check valid accepted response code - check whether the code is an array of number\n * @private\n * @param code\n */\nfunction checkValidAcceptCode(code) \{\n    if (!(code instanceof Array)) \{\n        return false;\n    \}\n\n    return code.every(function(item) \{\n        if (typeof item !== ''number'') \{\n            return false;\n        \}\n        return true;\n    \});\n\}\n\ngetTasks(5000);\n',
        'system', 1629698788504, 1629698788504);

insert into template
values (uuid(), 'get_smart.sh',
        '#!/bin/bash\n############################\n# Author: Peter.Pan@emc.com\n#############################\n\n# Check Root privillage\nif [[ \$EUID -ne 0 ]]; then\n   echo \"[Error]This script must be run as root\"\n   exit -1\nfi\n\n\nnr=0\ndeclare -a disk_array\n\n\nsmartctl --scan | while read line\ndo\n\n    #########################################\n    # smartctl --scan ( version 6.1) output as below\n    #\n    #\n    #/dev/sda -d scsi # /dev/sda, SCSI device\n    #/dev/sdb -d scsi # /dev/sdb, SCSI device\n    #/dev/sdc -d scsi # /dev/sdc, SCSI device\n    #/dev/sdd -d scsi # /dev/sdd, SCSI device\n    #/dev/bus/10 -d megaraid,8 # /dev/bus/10 [megaraid_disk_08], SCSI device\n    #/dev/bus/10 -d megaraid,9 # /dev/bus/10 [megaraid_disk_09], SCSI device\n    #/dev/bus/10 -d megaraid,13 # /dev/bus/10 [megaraid_disk_13], SCSI device\n    #/dev/bus/10 -d megaraid,14 # /dev/bus/10 [megaraid_disk_14], SCSI device\n    #########################################\n\n\n    # save the first column --  the device\n    my_dev=\$(echo \$line |awk ''\{print \$1 \}'')\n\n    # save the 3rd column  -- the device-type\n    # \"-d\" type will be : ata, scsi, sat[,auto][,N][+TYPE], usbcypress[,X], usbjmicron[,p][,x][,N], usbsunplus, marvell, areca,N/E, 3ware,N, hpt,L/M/N, megaraid,N, cciss,N, auto, test <=======\n    my_type=\$(echo \$line |awk ''\{print \$3 \}'')\n\n\n    type_param=\$my_type\n    # we want to get all SMART data, instead of scsi only , for sat only.\n    if [ \"\$my_type\"_ == \"ata\"_ ] || [ \"\$my_type\"_ == \"scsi\"_ ] || [ \"\$my_type\"_ == \"sat\"_ ] ; then\n        type_param=''auto''\n    fi\n\n    echo \"####\"\"\$my_dev \"\"\$my_type\" # this is an \"index\" for script parser, \"####\" is used to indicates the start of a devices\n\n    # execute the SMART tool to retrieve SMART for this device\n    my_smart=\$( smartctl -a -d \$type_param    \$my_dev )\n\n    # check SN, to reduce the duplicated lines (example, the /dev/sdc may be duplicated as megaraid,8, if it''s a \"JBOD\" connection to RAID )\n\n    my_SN=\$( echo \"\$my_smart\" |grep Serial|awk ''\{print \$3\}'')  # NOTE, the quote for \"\$var\" is important, to keep the newline in \$var variable\n    my_Vendor=\$( echo \"\$my_smart\" |grep Vendor|awk ''\{print \$3\}'')\n\n    is_duplicate=\$(  echo \"\$\{disk_array[@]\}\" | grep -w \"\$my_SN\"  );\n\n    if [ \"my_SN\"_  !=  \"\"_ ] && [ \$is_duplicate ] ; then\n        echo \"[Debug] duplicated disk item, skip this item\"\n        continue;\n    else\n        echo \"\$my_smart\"\n\n        disk_array[\$nr]=\"\$my_SN\"\n        nr=\$((\$nr+1))\n\n        #####################################\n        # Adding controller information\n        #\n        # Added by Ted.Chen@emc.com\n        #\n        # Controller information including:\n        #     controller_name - Example: LSI Logic / Symbios Logic MegaRAID SAS-3 3108 [Invader] (rev 02).\n        #     controller_PCI_BDF: The PCIe domain:bus:device.function ID of the SAS controller.\n        #     host_ID - The scsi host ID read from /sys/class/scsi_host/hostx\n        ####################################\n\n        is_megaraid=\$(  echo \"\$\{my_type\}\" | grep -w \"megaraid\" );\n\n        if [ \$is_megaraid ] ; then \t\t\t# Seeking for HDDs with megaraid type\n            # \$line example :\n            #   \$line = /dev/bus/0 -d megaraid,1 # /dev/bus/0 [megaraid_disk_01], SCSI device\n            my_ctrl_num=\$( echo \"\$line\" | awk ''\{print \$1\}'' | awk -F / ''\{print \$4\}'');    #The host ID\n        else # HDDs other than megaraid type\n            # example :\n            #   \$line = /dev/sda -d scsi # /dev/sda, SCSI device''\n            my_disk_name=\$( echo \"\$line\" | awk ''\{print \$1\}'');    #The disk name, ie. /dev/sda\n            # example of lsscsi output: [10:0:0:0]   disk    ATA      SATADOM-SV 3SE   710   /dev/sda\n            my_ctrl_num=\$(lsscsi | grep \$my_disk_name | awk -F : ''\{print \$1\}'' | awk -F [ ''\{print \$2\}'' );\n        fi\n\n        # example of output of readlink:\n        # : ../../devices/pci0000:00/0000:00:03.2/0000:07:00.0/host0/scsi_host/host0\n        # or: ../../devices/pci0000:00/0000:00:11.4/ata1/host1/scsi_host/host1\n        my_ctrl_bdf=\$(readlink /sys/class/scsi_host/host\$my_ctrl_num | grep -o ''[0-9a-z]\\+:[0-9a-z]\\+:[0-9a-z]\\+.[0-9a-z]\\+'' | tail -n 1);\n        my_ctrl_name=\$(lspci -s \$my_ctrl_bdf | awk -F : ''\{print \$3\}'');\n\n        echo \"###\"\"HBA Controller Information for \$my_dev \$my_type\";\n        echo \"controller_name=\"\"\$my_ctrl_name\";\n        echo \"controller_PCI_BDF=\"\"\$my_ctrl_bdf\";\n        echo \"host_ID=\"\"\$my_ctrl_num\";\n        continue;\n    fi\n\ndone',
        'system', 1629698788504, 1629698788504);

insert into profile
values (uuid(), 'boilerplate.ipxe',
        '#!ipxe\nset user-class MonoRail\n\necho\necho MonoRail Boilerplate iPXE...\nset syslog <%=server%>\n\n# Interface that requested an IP originally.\nset interface <%=macaddress%>\n\n# If macaddress is null, don''t need to find boot interface\nisset $\{interface\} || goto ifConfigured\n\n# Reboot Interval\nset rebootInterval:int8 5\n\n# Interface Search Index.\nset ifIndex:int8 0\nset ifIndexMax:int8 10\n\n# Interface Boot Retries\nset ifBootAttempt:int8 0\nset ifBootAttemptMax:int8 5\n\n# Close all the interfaces to begin with.\nifclose\n\n# Iterate the interfaces to find a match by MAC Address.\n:ifFind\niseq $\{ifIndex\} $\{ifIndexMax\} && goto ifFindFailure || goto ifFindContinue\n:ifFindContinue\niseq $\{interface\} $\{net$\{ifIndex\}/mac\} && goto ifBoot || inc ifIndex && goto ifFind\n\n# Boot the found interface.\n:ifBoot\niseq $\{ifBootAttempt\} $\{ifBootAttemptMax\} && goto ifBootFailure || goto ifBootContinue\n:ifBootContinue\nifopen net$\{ifIndex\}\nifconf net$\{ifIndex\} && goto ifConfigured || inc ifBootAttempt && goto ifBoot\n\n# Find Interface Failure\n:ifFindFailure\necho Unable to locate interface $\{interface\}, restarting in $\{rebootInterval\} seconds.\nsleep $\{rebootInterval\}\nreboot\n\n# Boot Interface Failure\n:ifBootFailure\necho Unable to boot interface $\{interface\}, restarting in $\{rebootInterval\} seconds.\nsleep $\{rebootInterval\}\nreboot\n\n# Configure the booted interface\n:ifConfigured\nroute\necho MonoRail Boilerplate iPXE Completed.\necho\n',
        'system', 1629698788504, 1629698788504);

insert into template
values (uuid(), 'centos.rackhdcallback',
        '#! /bin/bash\n#\n# centos.rackhdcallback       callback to rackhd post installation API hook\n#\n# description: calls back to rackhd post installation API hook\n#\n### BEGIN INIT INFO\n# Provides: centos.rackhdcallback\n# Required-Start:    $network\n# Default-Start:     3 4 5\n# Short-Description: Callback to rackhd post installation API hook\n# Description: Callback to rackhd post installation API hook\n### END INIT INFO\n\n\n# We can''t really know when networking is actually up and running from\n# a simple \"Required-Start: $network\", so instead just use curl with\n# a bunch of retries and hope it works. We could use more sophisticated\n# dependency mechanisms provided by systemd, but ideally we can just use\n# a single script to service both CentOS 6.5 and CentOS 7 installs, hence\n# reasoning for using `wget --retry-connrefused` below. Using `curl --retry`\n# fails immediately because it only handles connection timeouts, not connection\n# refused cases.\n# See https://www.freedesktop.org/wiki/Software/systemd/NetworkTarget/\n\n# Nothing wrong with set -e here since we''re not doing anything complex\nset -e\n/etc/init.d/network restart\necho \"Attempting to call back to RackHD CentOS installer\"\nwget --retry-connrefused --waitretry=1 -t 300 --post-data ''{\"nodeId\":\"<%=nodeId%>\"}'' --header=''Content-Type:application/json'' http://<%=server%>:<%=port%>/api/current/notification\n# Only run this once to verify the OS was installed, then disable it forever\nchkconfig centos.rackhdcallback off',
        'system', 1629698788504, 1629698788504);

CREATE TABLE catalog
(
    id            VARCHAR(50) NOT NULL,
    bare_metal_id VARCHAR(50) NOT NULL,
    source        VARCHAR(50) NOT NULL COMMENT 'source',
    `data`        MEDIUMTEXT COMMENT 'data',
    create_time   BIGINT      NOT NULL,
    PRIMARY KEY (id)
);


INSERT INTO `rackshift`.`template` (`id`, `NAME`, `content`, `type`, `create_time`, `update_time`) VALUES ('1c7d1c7e-cedc-45dc-8529-d18fb1c97b7f', 'debian-interfaces', '# Copyright 2017, Dell EMC, Inc.\n# This file describes the network interfaces available on your system\n# and how to activate them. For more information, see interfaces(5).\n\nsource /etc/network/interfaces.d/*\n\n# The loopback network interface\nauto lo\niface lo inet loopback\n\n<%_ if (typeof networkDevices !== ''undefined、'' && networkDevices.length > 0) \{ _%>\n    <%_ networkDevices.forEach(function(n) \{ _%>\n        <%_ for (p in n) \{ _%>\n            <%_ ip = n[p]; _%>\n            <%_ if ([''ipv4'', ''ipv6''].indexOf(p) === -1 || undefined == ip) continue; _%>\n            <%_ if (undefined !== ip.vlanIds) \{ _%>\n                <%_ ip.vlanIds.forEach(function(vid) \{ _%>\n                    <%_ if (p === ''ipv4'') \{ _%>\nauto <%=n.device%>.<%=vid%>\niface <%=n.device%>.<%=vid%> inet static\naddress <%=ip.ipAddr%>\nnetmask <%=ip.netmask%>\n                    <%_ \} else \{ _%>\nauto <%=n.device%>.<%=vid%>\niface <%=n.device%>.<%=vid%> inet6 static\naddress <%=ip.ipAddr%>\nnetmask <%=ip.prefixlen%>\n                    <%_ \} _%>\ngateway <%=ip.gateway%>\nvlan-raw-device <%=n.device%>\n                <%_ \}); _%>\n            <%_ \} else \{ _%>\n                     <%_ if (p === ''ipv4'') \{ _%>\nauto <%=n.device%>\niface <%=n.device%> inet static\naddress <%=ip.ipAddr%>\nnetmask <%=ip.netmask%>\n                    <%_ \} else \{ _%>\nauto <%=n.device%>\niface <%=n.device%> inet6 static\naddress <%=ip.ipAddr%>\nnetmask <%=ip.prefixlen%>\n                    <%_ \} _%>\ngateway <%=ip.gateway%>\n            <%_ \} _%>\n        <%_ \} _%>\n    <%_ \}); _%>\n<%_ \} _%>\n\n<% if (typeof dnsServers !== ''undefined、'' && dnsServers.length > 0) \{ -%>\ndns-nameservers <%=dnsServers.join('' '')%>\n<% \} -%>\n', 'system', 1635504807792, 1635504807792);

INSERT INTO `rackshift`.`template` (`id`, `NAME`, `content`, `type`, `create_time`, `update_time`) VALUES ('b6fdf1a8-2525-4254-a3bd-23df994a66af', 'debian-sources', '# Copyright 2017, Dell EMC, Inc.\n<% if ( osName === ''ubuntu'' ) \{ %>\n# See http://help.ubuntu.com/community/UpgradeNotes for how to upgrade to\n# newer versions of the distribution.\ndeb http://us.archive.ubuntu.com/ubuntu/ <%=version%> main restricted\ndeb-src http://us.archive.ubuntu.com/ubuntu/ <%=version%> main restricted\n\n## Major bug fix updates produced after the final release of the\n## distribution.\ndeb http://us.archive.ubuntu.com/ubuntu/ <%=version%>-updates main restricted\ndeb-src http://us.archive.ubuntu.com/ubuntu/ <%=version%>-updates main restricted\n\n## N.B. software from this repository is ENTIRELY UNSUPPORTED by the Ubuntu\n## team. Also, please note that software in universe WILL NOT receive any\n## review or updates from the Ubuntu security team.\ndeb http://us.archive.ubuntu.com/ubuntu/ <%=version%> universe\ndeb-src http://us.archive.ubuntu.com/ubuntu/ <%=version%> universe\ndeb http://us.archive.ubuntu.com/ubuntu/ <%=version%>-updates universe\ndeb-src http://us.archive.ubuntu.com/ubuntu/ <%=version%>-updates universe\n\n## N.B. software from this repository is ENTIRELY UNSUPPORTED by the Ubuntu\n## team, and may not be under a free licence. Please satisfy yourself as to\n## your rights to use the software. Also, please note that software in\n## multiverse WILL NOT receive any review or updates from the Ubuntu\n## security team.\ndeb http://us.archive.ubuntu.com/ubuntu/ <%=version%> multiverse\ndeb-src http://us.archive.ubuntu.com/ubuntu/ <%=version%> multiverse\ndeb http://us.archive.ubuntu.com/ubuntu/ <%=version%>-updates multiverse\ndeb-src http://us.archive.ubuntu.com/ubuntu/ <%=version%>-updates multiverse\n\n## N.B. software from this repository may not have been tested as\n## extensively as that contained in the main release, although it includes\n## newer versions of some applications which may provide useful features.\n## Also, please note that software in backports WILL NOT receive any review\n## or updates from the Ubuntu security team.\ndeb http://us.archive.ubuntu.com/ubuntu/ <%=version%>-backports main restricted universe multiverse\ndeb-src http://us.archive.ubuntu.com/ubuntu/ <%=version%>-backports main restricted universe multiverse\n\ndeb http://security.ubuntu.com/ubuntu <%=version%>-security main restricted\ndeb-src http://security.ubuntu.com/ubuntu <%=version%>-security main restricted\ndeb http://security.ubuntu.com/ubuntu <%=version%>-security universe\ndeb-src http://security.ubuntu.com/ubuntu <%=version%>-security universe\ndeb http://security.ubuntu.com/ubuntu <%=version%>-security multiverse\ndeb-src http://security.ubuntu.com/ubuntu <%=version%>-security multiverse\n\n## Uncomment the following two lines to add software from Canonical''s\n## ''partner'' repository.\n## This software is not part of Ubuntu, but is offered by Canonical and the\n## respective vendors as a service to Ubuntu users.\n# deb http://archive.canonical.com/ubuntu <%=version%> partner\n# deb-src http://archive.canonical.com/ubuntu <%=version%> partner\n\n## Uncomment the following two lines to add software from Ubuntu''s\n## ''extras'' repository.\n## This software is not part of Ubuntu, but is offered by third-party\n## developers who want to ship their latest software.\n# deb http://extras.ubuntu.com/ubuntu <%=version%> main\n# deb-src http://extras.ubuntu.com/ubuntu <%=version%> main\n<% \} else \{ %>\n#\n### Official Debian Repos \ndeb http://deb.debian.org/debian/ <%=version%> main contrib non-free \ndeb-src http://deb.debian.org/debian <%=version%> main contrib non-free\n\ndeb http://deb.debian.org/debian <%=version%>-updates main contrib non-free\ndeb-src http://deb.debian.org/debian <%=version%>-updates main contrib non-free\n\ndeb http://deb.debian.org/debian-security <%=version%>/updates main\ndeb-src http://deb.debian.org/debian-security <%=version%>/updates main\n\ndeb http://ftp.debian.org/debian <%=version%>-backports main\ndeb-src http://ftp.debian.org/debian <%=version%>-backports main\n<% \} %>\n', 'system', 1635504838386, 1635504838386);

INSERT INTO `rackshift`.`template` (`id`, `NAME`, `content`, `type`, `create_time`, `update_time`) VALUES ('bad00943-d6b8-4519-8443-7f010454a55e', 'post-install-debian.sh', '#!/bin/bash\n# Copyright 2015-2017, Dell EMC, Inc.\n# create SSH key for root\n<% if (''undefined'' !== typeof rootSshKey && null !== rootSshKey) \{ -%>\nmkdir /root/.ssh\necho <%=rootSshKey%> > /root/.ssh/authorized_keys\nchown -R root:root /root/.ssh\n<% } -%>\n\n# create users and SSH key for users\n<% if (typeof users !== ''undefined'') \{ -%>\n<% users.forEach(function(user) \{ -%>\n    <%_ if (undefined !== user.uid) \{ _%>\n        useradd -u <%=user.uid%> -m -p ''<%-user.encryptedPassword%>'' <%=user.name%>\n    <%_ } else \{_%>\n        useradd -m -p ''<%-user.encryptedPassword%>'' <%=user.name%>\n    <%_ } _%>\n    <%_ if (undefined !== user.sshKey) \{ _%>\nmkdir /home/<%=user.name%>/.ssh\necho <%=user.sshKey%> > /home/<%=user.name%>/.ssh/authorized_keys\nchown -R <%=user.name%>:<%=user.name%> /home/<%=user.name%>/.ssh\n    <%_ } _%>\n<% }); -%>\n<% } -%>\n\n', 'system', 1635504963193, 1635504963193);

INSERT INTO `rackshift`.`template` (`id`, `NAME`, `content`, `type`, `create_time`, `update_time`) VALUES ('f59d31d3-4615-49ce-9d83-84d124dd9810', 'debian.rackhdcallback', '#! /bin/bash\n# Copyright 2015-2017, Dell EMC, Inc.\n\n### BEGIN INIT INFO\n# Provides:          RackHDCallback\n# Required-Start:    $all\n# Required-Stop:\n# Default-Start:     2 3 4 5\n# Default-Stop:      0 1 6\n# Short-Description: RackHD callback\n# Description:       RackHD callback to give RackHD feedback that reboot is done.\n### END INIT INFO\n\necho \"Attempting to call back to RackHD Debian/Ubuntu installer\"\nwget --retry-connrefused --waitretry=1 -t 300 --post-data ''\{\"nodeId\":\"<%=nodeId%>\"\}'' --header=''Content-Type:application/json'' http://<%=server%>:<%=port%>/api/current/notification\n\n# remove file\nrm /etc/init.d/RackHDCallback\nupdate-rc.d RackHDCallback remove\n', 'system', 1635504929200, 1635504929200);

INSERT INTO `rackshift`.`template` (`id`, `NAME`, `content`, `type`, `create_time`, `update_time`) VALUES ('9bc5170f-1799-4a13-b021-425db1d0b4fe', 'winpe-kickstart.ps1', '# Copyright 2016-2018, Dell EMC, Inc.\n# The progress notification is just something nice-to-have, so progress notification failure should\n# never impact the normal installation process\n<% if( typeof progressMilestones !== ''undefined'' && progressMilestones.startInstallerUri ) \{ %>\n# the url may contain query, the symbol ''&'' will mess the command line logic, so the whole url need be wrapped in quotation marks\ntry\n\{\n    curl -UseBasicParsing -Method POST -ContentType ''application/json'' \"http://<%=server%>:<%=port%><%-progressMilestones.startInstallerUri%>\"\n\}\ncatch\n\{\n    echo \"Failed to notify the current progress: <%=progressMilestones.startInstaller.description%>\"\n\}\n<% \} %>\n$repo = \"<%=smbRepo%>\"\n$smb_passwd = \"<%-smbPassword%>\"\n$smb_user = \"<%=smbUser%>\"\nStart-Sleep -s 2\n\ntry \{\n    # These are non terminate commands and cannot be caught directly, so use exit code to terminate them when error\n    $out = net use w: $\{repo\} $\{smb_passwd\} /user:\\$\{smb_user\} 2>&1\n    if ($LASTEXITCODE) \{\n        throw $out\n    \}\n    Start-Sleep -s 2\n    $out = w:\\setup.exe /unattend:x:\\Windows\\System32\\unattend.xml 2>&1\n    if ($LASTEXITCODE) \{\n        throw $out\n    \}\n\}\ncatch \{\n    echo $_.Exception.Message\n    $body = @\{\n        error = $_.Exception.Message\n    \}\n\n    Invoke-RestMethod -Method Post -Uri ''http://<%=server%>:<%=port%>/api/2.0/notification?nodeId=<%=nodeId%>&status=fail'' -ContentType ''application/json'' `\n        -body (ConvertTo-Json $body) -Outfile winpe-kickstart.log\n    exit 1\n\}\n\ncurl -UseBasicParsing -Method POST -ContentType ''application/json'' http://<%=server%>:<%=port%>/api/current/notification?nodeId=<%=nodeId%> -Outfile winpe-kickstart.log\n\n', 'system', 1635562518556, 1635562518556);

INSERT INTO `rackshift`.`template` (`id`, `NAME`, `content`, `type`, `create_time`, `update_time`) VALUES ('497ce545-65b9-4b83-8ab5-e5ae3552f52b', 'user-data.yaml', '#cloud-config\n\nautoinstall:\n  version: 1\n  identity:\n    hostname: <%=hostname%>\n    password: $6$FhcddHFVZ7ABA4Gi$9l4yURWASWe8xEa1jzI0bacVLvhe3Yn4/G3AnU11K3X0yu/mICVRxfo6tZTB2noKljlIRzjkVZPocdf63MtzC0\n    username: ubuntu\n  locale: en_US\n  ssh:\n    install-server: yes\n  network:\n    network:\n      version: 2\n      ethernets:\n<% if (typeof networkDevices !== ''undefined'') \{ -%>\n<%  networkDevices.forEach(function(n, index)\{ -%>\n        eth<%=index%>:\n          match:\n            macaddress: <%=n.device%>\n          set-name: eth<%=index%>\n          addresses:\n            - <%=n.ipv4.ipAddr%>/24\n          gateway4: <%=n.ipv4.gateway%>\n          nameservers: \n            addresses: [<%=n.ipv4.dnsServers%>]\n<%   \}) -%>\n<% \} -%>\n  late-commands:\n    - curl -X POST -H ''Content-Type:application/json'' http://<%=server%>:<%=port%>/api/current/notification?nodeId=<%=nodeId%>\n    - wget http://<%=server%>:<%=port%>/api/current/templates/<%=rackhdCallbackScript%>?nodeId=<%=nodeId%> -O /target/etc/init.d/RackHDCallback\n    - chmod +x /target/etc/init.d/RackHDCallback\n    - curtin in-target --target=/target -- update-rc.d RackHDCallback defaults;\n', 'system', 1635604755853, 1635604755853);