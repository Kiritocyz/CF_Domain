# CF_Domain
这是一个搭配[XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest/)的、在本地运行的自制优选域名脚本，通过任务计划和vbs实现定时后台无感运行。
## 使用前提
+ 本项目只适用于***windows系统***
+ 需要***powershell升级到7.0***以上
+ 具有cf账号，且***有托管的域名***
## 快速使用
1. 将本项目的3个文件解压放至从[XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest/)获得的***CloudflareST.exe同一目录***下
2. 填写好cf_domain_cfg.ini中的参数
3. 双击cf_domain.bat即可运行
## cf_domain_cfg.ini中的参数解释
+ API_TOKEN——填写你在cf上创建的一个具有编辑DNS权限的API令牌，如何创建请自行查阅
+ ZONE_ID——填写你要使用的、托管在cf中的域名的区域ID，具体位置请自行查阅
+ SUB_DOMAIN——填写你要添加A记录的子域名
+ REQUIRED_COUNT——填写你对该子域名要添加的A记录的数量，要求***整数***，默认为1
+ TEST_SPEED——填写对A记录ip速度最低要求，要求***整数***，默认为0
+ TEST_URL——填写CloudflareST.exe使用的测速URL，默认为[XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest/)的https://cf.xiu2.xyz/url ，可换成自建的测速URL，自建具体参考https://github.com/cmliu/CF-Workers-SpeedTestURL
+ POWERSHELL_NAME——填写系统中powershell目录下exe文件的名字，默认为pwsh（本人升级7版本时，默认为pwsh.exe），如果你已更改回powershell.exe，请更改此处为powershell
## 定时后台无感运行
1. 将cf_domain.vbs中的cf_domain.bat的***绝对路径***填写完好
2. 创建计划任务，选择***创建任务***，填好名称，勾选***使用最高权限运行***
3. 新建触发器，选择你要运行的时间，如果你***想间隔一段时间运行，勾选重复任务间隔***，下拉时间选项最多只有1小时，想要更长时间间隔需要***手敲***（是的，你没看错）
4. 新建操作，选择***启动程序***，**程序或脚本**填写***wscript.exe***，**添加参数**写"完整的绝对目录\cf_domain.vbs"（***需要英文引号***），**起始于**填写前面的完整的绝对目录（***不要英文引号***），注意此目录也是***CloudflareST.exe***所在文件夹
5. 保存此计划任务即可定时后台无感运行，每次运行完毕会输出日志到cf_domain.log中，当前域名拥有A记录可在cf_dns.csv中查看。
