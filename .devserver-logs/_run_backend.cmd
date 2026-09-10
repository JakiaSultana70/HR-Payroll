@echo off
cd /d "C:\Users\Hp\Desktop\Project_HRPayroll\payroll-automation-backend"
call .\mvnw.cmd -q -o spring-boot:run -Dspring-boot.run.profiles=dev > "C:\Users\Hp\Desktop\Project_HRPayroll\.devserver-logs\backend.log" 2>&1
