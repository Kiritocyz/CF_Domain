@echo off
chcp 65001 > nul
setlocal EnableDelayedExpansion

:: ============================================================
:: 读取INI配置文件
:: ============================================================
for /f "usebackq tokens=1,2 delims==" %%a in ("cf_domain_cfg.ini") do (
    if "%%a"=="API_TOKEN" set "API_TOKEN=%%b"
    if "%%a"=="ZONE_ID" set "ZONE_ID=%%b"
    if "%%a"=="SUB_DOMAIN" set "SUB_DOMAIN=%%b"
    if "%%a"=="REQUIRED_COUNT" set "REQUIRED_COUNT=%%b"
    if "%%a"=="TEST_SPEED" set "TEST_SPEED=%%b" && if "!TEST_SPEED!" neq "" set "TEST_SPEED=-sl !TEST_SPEED!"
    if "%%a"=="MIN_DELAY" set "MIN_DELAY=%%b" && if "!MIN_DELAY!" neq "" set "MIN_DELAY=-tll !MIN_DELAY!"
    if "%%a"=="MAX_DELAY" set "MAX_DELAY=%%b" && if "!MAX_DELAY!" neq "" set "MAX_DELAY=-tl !MAX_DELAY!"
    if "%%a"=="TEST_URL" set "TEST_URL=%%b" && if "!TEST_URL!" neq "" set "TEST_URL=-url !TEST_URL!"
    if "%%a"=="POWERSHELL_NAME" set "POWERSHELL_NAME=%%b"
    if "%%a"=="DEBUG" set "DEBUG=%%b" && if "!DEBUG!"=="1" (set "DEBUG=-debug") else set "DEBUG="
    if "%%a"=="CFCOLO" set "CFCOLO=%%b" && if "!CFCOLO!" neq "" set "CFCOLO=-httping -cfcolo !CFCOLO!"
)

:: ============================================================
:: 参数校验
:: ============================================================
if not defined API_TOKEN (
    echo API_TOKEN不能为空！
    goto :cleanup_exit
)
if not defined ZONE_ID (
    echo ZONE_ID不能为空！
    goto :cleanup_exit
)
if not defined SUB_DOMAIN (
    echo SUB_DOMAIN不能为空！
    goto :cleanup_exit
)
if not defined REQUIRED_COUNT (
    echo REQUIRED_COUNT不能为空！
    goto :cleanup_exit
)
if !REQUIRED_COUNT! leq 0 (
    echo REQUIRED_COUNT需要一个大于0的数！
    goto :cleanup_exit
)

:: ============================================================
:: 获取现有DNS记录
:: ============================================================
echo Fetching existing DNS records...
curl -s -X GET "https://api.cloudflare.com/client/v4/zones/%ZONE_ID%/dns_records?name=%SUB_DOMAIN%" -H "Authorization: Bearer %API_TOKEN%" -H "Content-Type: application/json" -o curl_temp.json

if not exist "curl_temp.json" (
    echo %date%, %time%: Failed to retrieve DNS records for %SUB_DOMAIN% from Cloudflare. >> cf_domain.log
    goto :cleanup_exit
)

:: 提取现有A记录的IP（用,分隔）
set "dns_ips="
for /f "delims=" %%j in ('%POWERSHELL_NAME% -NoProfile -Command "(Get-Content 'curl_temp.json' | ConvertFrom-Json).result | Where-Object {$_.type -eq 'A'} | Select-Object -ExpandProperty content"') do (
    set "dns_ips=!dns_ips!,%%j"
)
if defined dns_ips set "dns_ips=!dns_ips:~1!"

echo Existing DNS IPs: !dns_ips!
pause
:: 选择测速工具
if exist "CloudflareST.exe" (
    set "cfst=CloudflareST.exe"
) else (
    set "cfst=cfst.exe"
)

:: ============================================================
:: 对现有IP进行测速
:: ============================================================
if defined dns_ips (
    echo.|!cfst! %DEBUG% %CFCOLO% -ip !dns_ips! -o cf_dns.csv -p %REQUIRED_COUNT% %TEST_SPEED% %MIN_DELAY% %MAX_DELAY% -dn %REQUIRED_COUNT% %TEST_URL%
) else (
    echo No existing DNS IPs to test.
)
echo.

:: 统计测速通过的IP数量
set "ok_ips="
set "ip_count=0"
if exist "cf_dns.csv" (
    for /f "skip=1 tokens=1 delims=," %%m in (cf_dns.csv) do (
        set "ok_ips=!ok_ips! %%m"
        set /a ip_count+=1
    )
)

echo Current valid DNS IP count: !ip_count!

:: ============================================================
:: 如果IP数量不够，从ip.txt获取新增IP
:: ============================================================
set /a needed_count=REQUIRED_COUNT-ip_count
if !needed_count! gtr 0 (
    echo Need to fetch !needed_count! more IP addresses...
    echo.|!cfst! %DEBUG% %CFCOLO% -f ip.txt -o add.csv %TEST_SPEED% %MIN_DELAY% %MAX_DELAY% -dn !needed_count! %TEST_URL%
    echo.
    set "new_ips="
    if exist "add.csv" (
        for /f "skip=1 tokens=1 delims=," %%n in (add.csv) do (
            set "new_ips=!new_ips! %%n"
        )
    )
    echo Additional IPs fetched: !new_ips!

    :: 将新IP添加到Cloudflare DNS记录中
    for %%p in (!new_ips!) do (
        echo Adding A record for %SUB_DOMAIN% with IP %%p...
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/%ZONE_ID%/dns_records" ^
            -H "Authorization: Bearer %API_TOKEN%" ^
            -H "Content-Type: application/json" ^
            --data "{\"type\":\"A\",\"name\":\"%SUB_DOMAIN%\",\"content\":\"%%p\",\"ttl\":1,\"proxied\":false}" >nul
        echo Successfully added A record for %SUB_DOMAIN% with IP %%p.
    )
) else (
    echo No need to fetch additional IPs.
)

:: ============================================================
:: 标记需要删除的DNS记录（在现有记录中但未通过测速的IP）
:: ============================================================
set "to_delete="
for %%a in (!dns_ips!) do (
    set "_found=0"
    for %%k in (!ok_ips!) do (
        if "%%k"=="%%a" set "_found=1"
    )
    if !_found!==0 (
        echo Marking %%a for deletion...
        set "to_delete=!to_delete! %%a"
    )
)

:: ============================================================
:: 删除多余的DNS记录
:: ============================================================
if not defined to_delete (
    echo No DNS records marked for deletion. Skipping deletion.
) else (
    :: 重建 cf_dns.csv，移除待删除的IP（精确匹配）
    if exist "cf_dns_deleted.csv" del "cf_dns_deleted.csv"
    if exist "cf_dns.csv" (
        for /f "tokens=1* delims=," %%d in (cf_dns.csv) do (
            set "_keep=1"
            for %%x in (!to_delete!) do (
                if "%%d"=="%%x" set "_keep=0"
            )
            if !_keep!==1 echo %%d,%%e >> cf_dns_deleted.csv
        )
    )
    if exist "cf_dns_deleted.csv" (
        move /y cf_dns_deleted.csv cf_dns.csv >nul
    ) else (
        echo cf_dns.csv > cf_dns.csv
    )

    :: 获取待删除记录的Cloudflare ID
    set "records_id="
    for /f "delims=" %%i in ('%POWERSHELL_NAME% -NoProfile -Command "$toDelete = '%to_delete%'.Split(' ',[System.StringSplitOptions]::RemoveEmptyEntries); (Get-Content 'curl_temp.json' | ConvertFrom-Json).result | Where-Object { $toDelete -contains $_.content } | Select-Object -ExpandProperty id"') do (
        set "records_id=!records_id! %%i"
    )

    :: 执行删除操作
    for %%i in (!records_id!) do (
        echo Deleting A record with ID %%i...
        curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/%ZONE_ID%/dns_records/%%i" ^
            -H "Authorization: Bearer %API_TOKEN%" ^
            -H "Content-Type: application/json" >nul
        echo Deleted %%i from %SUB_DOMAIN%.
    )
)

:: ============================================================
:: 合并新增IP到 cf_dns.csv，清理临时文件
:: ============================================================
if exist "add.csv" (
    for /f "skip=1 delims=" %%i in (add.csv) do (
        echo %%i >> cf_dns.csv
    )
    del add.csv
)
if exist "curl_temp.json" del curl_temp.json

:: 输出完成日志
echo %date%, %time%: 域名 %SUB_DOMAIN% 的优选IP更新完毕，详见 cf_dns.csv。 >> cf_domain.log
pause
echo Done.
goto :eof

:cleanup_exit
echo 按任意键退出
pause
goto :eof