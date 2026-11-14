# Install-Module Microsoft.Graph -Scope CurrentUser
Connect-MgGraph -Scopes "AuditLogsQuery.Read.All"

# --- 1. Crear la consulta ---
$body = @{
    displayName              = "Eliminaciones - usuario@dominio.com"
    filterStartDateTime      = (Get-Date).AddDays(-30).ToUniversalTime().ToString("o")
    filterEndDateTime        = (Get-Date).ToUniversalTime().ToString("o")
    userPrincipalNameFilters = @("usuario@dominio.com")
    operationFilters         = @("FileDeleted","FileRecycled",
                                 "FileDeletedFirstStageRecycleBin",
                                 "FileDeletedSecondStageRecycleBin",
                                 "FolderDeleted","FolderRecycled")
    recordTypeFilters        = @("sharePointFileOperation")
} | ConvertTo-Json

$query = Invoke-MgGraphRequest -Method POST `
    -Uri "https://graph.microsoft.com/v1.0/security/auditLog/queries" `
    -Body $body -ContentType "application/json"

$qid = $query.id
Write-Host "Consulta creada: $qid"

# --- 2. Esperar a que termine ---
do {
    Start-Sleep -Seconds 30
    $status = (Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/security/auditLog/queries/$qid").status
    Write-Host "Estado: $status"
} while ($status -in @("notStarted","running"))

# --- 3. Leer los registros, con paginación ---
$uri = "https://graph.microsoft.com/v1.0/security/auditLog/queries/$qid/records"
$registros = @()
do {
    $resp = Invoke-MgGraphRequest -Method GET -Uri $uri
    $registros += $resp.value
    $uri = $resp.'@odata.nextLink'
} while ($uri)

# --- 4. Exportar ---
$registros | ForEach-Object {
    [PSCustomObject]@{
        Fecha     = $_.createdDateTime
        Usuario   = $_.userPrincipalName
        Operacion = $_.operation
        Archivo   = $_.auditData.SourceFileName
        Ruta      = $_.objectId
        Sitio     = $_.auditData.SiteUrl
        IP        = $_.auditData.ClientIP
    }
} | Export-Csv .\eliminaciones_graph.csv -NoTypeInformation -Encoding UTF8