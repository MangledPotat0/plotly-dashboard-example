# Sales Dashboard Launch Script
# This script sets up a temporary PostgreSQL database, loads CSV data,
# and launches the sales dashboard web application

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Sales Dashboard Launch Script" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$POSTGRES_CONTAINER = "dashboard-test"
$POSTGRES_PASSWORD = "testpassword"
$POSTGRES_USER = "postgres"
$POSTGRES_DB = "sales_db"
$DASHBOARD_CONTAINER = "sales-dashboard-app"
$NETWORK_NAME = "dashboard-network"

# Step 1: Create Docker network
Write-Host "[1/7] Creating Docker network..." -ForegroundColor Yellow
docker network create $NETWORK_NAME 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Network created: $NETWORK_NAME" -ForegroundColor Green
} else {
    Write-Host "✓ Network already exists: $NETWORK_NAME" -ForegroundColor Green
}
Write-Host ""

# Step 2: Launch PostgreSQL container
Write-Host "[2/7] Launching PostgreSQL container..." -ForegroundColor Yellow
docker run -d `
    --name $POSTGRES_CONTAINER `
    --network $NETWORK_NAME `
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD `
    -e POSTGRES_USER=$POSTGRES_USER `
    -e POSTGRES_DB=$POSTGRES_DB `
    -p 5432:5432 `
    --rm `
    postgres:15-alpine

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ PostgreSQL container started: $POSTGRES_CONTAINER" -ForegroundColor Green
} else {
    Write-Host "✗ Failed to start PostgreSQL container" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 3: Wait for PostgreSQL to be ready
Write-Host "[3/7] Waiting for PostgreSQL to be ready..." -ForegroundColor Yellow
$maxAttempts = 30
$attempt = 0
$ready = $false

while ($attempt -lt $maxAttempts -and -not $ready) {
    $attempt++
    Start-Sleep -Seconds 1
    
    $result = docker exec $POSTGRES_CONTAINER pg_isready -U $POSTGRES_USER 2>$null
    if ($LASTEXITCODE -eq 0) {
        $ready = $true
        Write-Host "✓ PostgreSQL is ready!" -ForegroundColor Green
    } else {
        Write-Host "  Attempt $attempt/$maxAttempts..." -ForegroundColor Gray
    }
}

if (-not $ready) {
    Write-Host "✗ PostgreSQL failed to start in time" -ForegroundColor Red
    docker stop $POSTGRES_CONTAINER 2>$null
    exit 1
}
Write-Host ""

# Step 4: Create database tables
Write-Host "[4/7] Creating database tables..." -ForegroundColor Yellow

$createTablesSQL = @"
CREATE TABLE IF NOT EXISTS products (
    product_id INTEGER PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL
);

CREATE TABLE IF NOT EXISTS sales_data (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    product_id INTEGER NOT NULL,
    sales NUMERIC(10, 2) NOT NULL,
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

CREATE INDEX IF NOT EXISTS idx_sales_product_id ON sales_data(product_id);
CREATE INDEX IF NOT EXISTS idx_sales_date ON sales_data(date);
"@

docker exec -i $POSTGRES_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB -c "$createTablesSQL" > $null

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Database tables created successfully" -ForegroundColor Green
} else {
    Write-Host "✗ Failed to create tables" -ForegroundColor Red
    docker stop $POSTGRES_CONTAINER 2>$null
    exit 1
}
Write-Host ""

# Step 5: Load CSV data into database
Write-Host "[5/7] Loading CSV data into database..." -ForegroundColor Yellow

# Copy CSV files to container
docker cp data/products.csv ${POSTGRES_CONTAINER}:/tmp/products.csv
docker cp data/sales_data.csv ${POSTGRES_CONTAINER}:/tmp/sales_data.csv

# Load products
$loadProductsSQL = "COPY products(product_id, product_name) FROM '/tmp/products.csv' WITH (FORMAT csv, HEADER true);"
docker exec -i $POSTGRES_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB -c "$loadProductsSQL" > $null

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Products data loaded" -ForegroundColor Green
} else {
    Write-Host "✗ Failed to load products data" -ForegroundColor Red
    docker stop $POSTGRES_CONTAINER 2>$null
    exit 1
}

# Load sales data
$loadSalesSQL = "COPY sales_data(date, product_id, sales) FROM '/tmp/sales_data.csv' WITH (FORMAT csv, HEADER true);"
docker exec -i $POSTGRES_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB -c "$loadSalesSQL" > $null

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Sales data loaded" -ForegroundColor Green
} else {
    Write-Host "✗ Failed to load sales data" -ForegroundColor Red
    docker stop $POSTGRES_CONTAINER 2>$null
    exit 1
}

# Verify data
$productCount = docker exec -i $POSTGRES_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB -t -c "SELECT COUNT(*) FROM products;" | Out-String
$salesCount = docker exec -i $POSTGRES_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB -t -c "SELECT COUNT(*) FROM sales_data;" | Out-String

Write-Host "  - Products loaded: $($productCount.Trim())" -ForegroundColor Cyan
Write-Host "  - Sales records loaded: $($salesCount.Trim())" -ForegroundColor Cyan
Write-Host ""

# Step 6: Launch Flask application
Write-Host "[6/7] Launching Flask application..." -ForegroundColor Yellow

docker run -d `
    --name $DASHBOARD_CONTAINER `
    --network $NETWORK_NAME `
    -e DB_HOST=$POSTGRES_CONTAINER `
    -e DB_NAME=$POSTGRES_DB `
    -e DB_USER=$POSTGRES_USER `
    -e DB_PASSWORD=$POSTGRES_PASSWORD `
    -p 5050:5000 `
    --rm `
    sales-dashboard `
    python -m flask run --host=0.0.0.0 --port=5000

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Flask application started: $DASHBOARD_CONTAINER" -ForegroundColor Green
} else {
    Write-Host "✗ Failed to start Flask application" -ForegroundColor Red
    docker stop $POSTGRES_CONTAINER 2>$null
    exit 1
}

# Wait for Flask to start
Write-Host "  Waiting for Flask to initialize..." -ForegroundColor Gray
Start-Sleep -Seconds 3
Write-Host ""

# Step 7: Generate static HTML from Flask and serve with Python HTTP server
Write-Host "[7/7] Setting up web server on localhost:7777..." -ForegroundColor Yellow

# Create output directory
$outputDir = "docs/output"
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Fetch the dashboard HTML from Flask app
Write-Host "  Fetching dashboard from Flask app..." -ForegroundColor Gray
try {
    $maxRetries = 10
    $retry = 0
    $success = $false
    
    while ($retry -lt $maxRetries -and -not $success) {
        try {
            $dashboardHtml = Invoke-WebRequest -Uri "http://localhost:5050" -UseBasicParsing -TimeoutSec 5
            $success = $true
        } catch {
            $retry++
            Write-Host "    Retry $retry/$maxRetries..." -ForegroundColor Gray
            Start-Sleep -Seconds 2
        }
    }
    
    if ($success) {
        $dashboardHtml.Content | Out-File -FilePath "$outputDir/index.html" -Encoding UTF8
        Write-Host "✓ Dashboard HTML saved to $outputDir/index.html" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to fetch dashboard from Flask" -ForegroundColor Red
        docker stop $DASHBOARD_CONTAINER 2>$null
        docker stop $POSTGRES_CONTAINER 2>$null
        exit 1
    }
} catch {
    Write-Host "✗ Error fetching dashboard: $_" -ForegroundColor Red
    docker stop $DASHBOARD_CONTAINER 2>$null
    docker stop $POSTGRES_CONTAINER 2>$null
    exit 1
}

# Start Python HTTP server on port 7777
Write-Host "  Starting web server on port 7777..." -ForegroundColor Gray
Start-Process -FilePath "python" -ArgumentList "-m http.server 7777 --directory $outputDir" -WindowStyle Hidden

Start-Sleep -Seconds 2
Write-Host "✓ Web server started on http://localhost:7777" -ForegroundColor Green
Write-Host ""

# Summary
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "✓ SETUP COMPLETE!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Services Running:" -ForegroundColor Yellow
Write-Host "  • PostgreSQL:   dashboard-test (internal)" -ForegroundColor White
Write-Host "  • Flask App:    http://localhost:5050" -ForegroundColor White
Write-Host "  • Dashboard:    http://localhost:7777" -ForegroundColor White
Write-Host ""
Write-Host "Database Info:" -ForegroundColor Yellow
Write-Host "  • Host:         $POSTGRES_CONTAINER" -ForegroundColor White
Write-Host "  • Database:     $POSTGRES_DB" -ForegroundColor White
Write-Host "  • User:         $POSTGRES_USER" -ForegroundColor White
Write-Host "  • Products:     $($productCount.Trim())" -ForegroundColor White
Write-Host "  • Sales:        $($salesCount.Trim())" -ForegroundColor White
Write-Host ""
Write-Host "Press Ctrl+C to stop all services and cleanup..." -ForegroundColor Yellow
Write-Host ""

# Open browser
Write-Host "Opening dashboard in browser..." -ForegroundColor Cyan
Start-Process "http://localhost:7777"

# Wait for user interrupt
try {
    while ($true) {
        Start-Sleep -Seconds 1
    }
} finally {
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "Cleaning up..." -ForegroundColor Yellow
    Write-Host "=====================================" -ForegroundColor Cyan
    
    # Stop Python HTTP server
    Get-Process | Where-Object {$_.CommandLine -like "*http.server 7777*"} | Stop-Process -Force 2>$null
    Write-Host "✓ Web server stopped" -ForegroundColor Green
    
    # Stop Docker containers (they will auto-remove due to --rm flag)
    docker stop $DASHBOARD_CONTAINER 2>$null
    Write-Host "✓ Flask container stopped" -ForegroundColor Green
    
    docker stop $POSTGRES_CONTAINER 2>$null
    Write-Host "✓ PostgreSQL container stopped" -ForegroundColor Green
    
    # Remove network
    docker network rm $NETWORK_NAME 2>$null
    Write-Host "✓ Network removed" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "All services cleaned up successfully!" -ForegroundColor Green
}
