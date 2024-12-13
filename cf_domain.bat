@echo off
chcp 65001 > nul
setlocal EnableDelayedExpansion

for /f "usebackq tokens=1,2 delims==" %%a in ("cf_domain_cfg.ini") do (
    if "%%a"=="API_TOKEN" set "API_TOKEN=%%b"
    if "%%a"=="ZONE_ID" set "ZONE_ID=%%b"
    if "%%a"=="SUB_DOMAIN" set "SUB_DOMAIN=%%b"
    if "%%a"=="REQUIRED_COUNT" set "REQUIRED_COUNT=%%b"
    if "%%a"=="TEST_SPEED" set "TEST_SPEED=%%b"
    if "%%a"=="TEST_URL" set "TEST_URL=%%b"
    if "%%a"=="POWERSHELL_NAME" set "POWERSHELL_NAME=%%b"
)
echo Fetching existing DNS records...
curl -s -X GET "https://api.cloudflare.com/client/v4/zones/%ZONE_ID%/dns_records?name=%SUB_DOMAIN%" -H "Authorization: Bearer %API_TOKEN%" -H "Content-Type: application/json" -o curl_temp.json

if not exist "curl_temp.json" (
    echo %date%, %time%: Failed to retrieve DNS records for %SUB_DOMAIN% from Cloudflare. >> cf_domain.log
    exit /b
)

set "dns_ips="
for /f "delims=" %%j in ('%POWERSHELL_NAME% -Command "(Get-Content "curl_temp.json" | ConvertFrom-Json).result | Where-Object {$_.type -eq 'A' } | Select-Object -ExpandProperty content | ForEach-Object { $_ } | Join-String -Separator ','"') do (
    set "dns_ips=%%j"
)

echo Existing DNS IPs: !dns_ips!

echo.|CloudflareST.exe -ip !dns_ips! -o cf_dns.csv -p %REQUIRED_COUNT% -sl %TEST_SPEED% -dn %REQUIRED_COUNT% -url %TEST_URL%
echo.

set "ok_ips="
set "ip_count=0"
for /f "skip=1 tokens=1 delims=," %%m in (cf_dns.csv) do (
    set "ok_ips=!ok_ips! %%m"
    set /a ip_count+=1
)

echo Current valid DNS IP count: !ip_count!

set /a needed_count=%REQUIRED_COUNT%-!ip_count!
if !needed_count! gtr 0 (
	echo Need to fetch !needed_count! more IP addresses...
	echo.|CloudflareST.exe -f ip.txt -o 追加.csv  -sl %TEST_SPEED% -dn !needed_count! -url %TEST_URL%
	echo.
	set "new_ips="
	for /f "skip=1 tokens=1 delims=," %%n in (追加.csv) do (
		set "new_ips=!new_ips! %%n"
	)
	echo Additional IPs fetched: !new_ips!

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

set "to_delete="
for %%a in (!dns_ips!) do (
    echo !ok_ips! | findstr /c:"%%a" >nul
    if errorlevel 1 (
        echo Marking %%a for deletion...
        set "to_delete=!to_delete! %%a"
    )
)

if not defined to_delete (
    echo No DNS records marked for deletion. Skipping deletion.
) else (
	for /f "tokens=1* delims=," %%d in (cf_dns.csv) do (
		echo !to_delete! | findstr /c:"%%d" >nul
		if errorlevel 1 (
			echo %%d,%%e >> cf_dns_temp.csv
		)
	)
	move /y cf_dns_temp.csv cf_dns.csv >nul

        for /f "delims=" %%i in ('%POWERSHELL_NAME% -Command "& {$to_delete = '%to_delete%'.split(' ');(Get-Content 'curl_temp.json' | ConvertFrom-Json).result | Where-Object { $to_delete -contains $_.content } | Select-Object -ExpandProperty id}"') do (
        set "records_id=!records_id! %%i"
    )

        for %%i in (!records_id!) do (
        echo Deleting A record with ID %%i...
        curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/%ZONE_ID%/dns_records/%%i" ^
            -H "Authorization: Bearer %API_TOKEN%" ^
            -H "Content-Type: application/json" >nul
        echo Deleted %%i from %SUB_DOMAIN%.
    )
)

for /f "skip=1 delims=" %%i in (追加.csv) do (
	echo %%i >> cf_dns.csv
)
del 追加.csv

del curl_temp.json

echo %date%, %time%: 域名%SUB_DOMAIN%的优选ip更新完毕，查看此域名的A记录详见文件cf_dns.csv。 >> cf_domain.log

echo Done.
endlocal