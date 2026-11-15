<#
.SYNOPSIS
    Audita las eliminaciones de archivos y carpetas en SharePoint Online / OneDrive
    realizadas por uno o varios usuarios, usando la API de auditoría de Microsoft Graph.

.DESCRIPTION
    Crea una consulta en el registro de auditoría unificado de Microsoft 365, espera a
    que termine, descarga todos los registros (con paginación) y los exporta a CSV.

.PARAMETER UserPrincipalName
    UPN de uno o varios usuarios a auditar.

.PARAMETER Days
    Número de días hacia atrás a consultar (por defecto 30). Se ignora si se indica StartDate.

.PARAMETER StartDate
    Fecha de inicio del rango. Por defecto: ahora menos -Days.

.PARAMETER EndDate
    Fecha de fin del rango. Por defecto: ahora.

.PARAMETER OutputPath
    Ruta del archivo CSV de salida. Por defecto: .\eliminaciones_graph.csv

.PARAMETER PollSeconds
    Segundos entre cada comprobación del estado de la consulta (por defecto 30).

.PARAMETER TimeoutMinutes
    Tiempo máximo de espera para que la consulta termine (por defecto 60).

.EXAMPLE
    .\auditoria_usuarios.ps1 -UserPrincipalName usuario@dominio.com

.EXAMPLE
    .\auditoria_usuarios.ps1 -UserPrincipalName a@dominio.com, b@dominio.com -Days 7 -OutputPath C:\Temp\eliminaciones.csv
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string[]] $UserPrincipalName,

    [ValidateRange(1, 180)]
    [int] $Days = 30,

    [datetime] $StartDate,

    [datetime] $EndDate = (Get-Date),

    [string] $OutputPath = (Join-Path -Path (Get-Location) -ChildPath 'eliminaciones_graph.csv'),

    [ValidateRange(5, 600)]
    [int] $PollSeconds = 30,

    [ValidateRange(1, 1440)]
    [int] $TimeoutMinutes = 60
)

$ErrorActionPreference = 'Stop'

$graphBase     = 'https://graph.microsoft.com/v1.0/security/auditLog/queries'
$requiredScope = 'AuditLogsQuery.Read.All'

if (-not $PSBoundParameters.ContainsKey('StartDate')) {
    $StartDate = $EndDate.AddDays(-$Days)
}
if ($StartDate -ge $EndDate) {
    throw "StartDate ($StartDate) debe ser anterior a EndDate ($EndDate)."
}

# --- 0. Módulo y conexión ---
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    throw "Falta el módulo Microsoft.Graph. Instálalo con: Install-Module Microsoft.Graph -Scope CurrentUser"
}

$context = Get-MgContext
if (-not $context -or $context.Scopes -notcontains $requiredScope) {
    Connect-MgGraph -Scopes $requiredScope -NoWelcome
}

# --- 1. Crear la consulta ---
$body = @{
    displayName              = "Eliminaciones - $($UserPrincipalName -join ', ') - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    filterStartDateTime      = $StartDate.ToUniversalTime().ToString('o')
    filterEndDateTime        = $EndDate.ToUniversalTime().ToString('o')
    userPrincipalNameFilters = @($UserPrincipalName)
    operationFilters         = @(
        'FileDeleted', 'FileRecycled',
        'FileDeletedFirstStageRecycleBin', 'FileDeletedSecondStageRecycleBin',
        'FolderDeleted', 'FolderRecycled'
    )
    recordTypeFilters        = @('sharePointFileOperation')
} | ConvertTo-Json -Depth 5

$query = Invoke-MgGraphRequest -Method POST -Uri $graphBase -Body $body -ContentType 'application/json'
$qid   = $query.id
Write-Host "Consulta creada: $qid"
Write-Host "Rango: $($StartDate.ToString('g')) - $($EndDate.ToString('g'))"

# --- 2. Esperar a que termine ---
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
do {
    if ((Get-Date) -gt $deadline) {
        throw "La consulta $qid no terminó en $TimeoutMinutes minutos. Puedes consultarla más tarde en $graphBase/$qid"
    }
    Start-Sleep -Seconds $PollSeconds
    $status = (Invoke-MgGraphRequest -Method GET -Uri "$graphBase/$qid").status
    Write-Host "$(Get-Date -Format 'HH:mm:ss') Estado: $status"
} while ($status -in @('notStarted', 'running'))

if ($status -ne 'succeeded') {
    throw "La consulta $qid terminó con estado '$status'."
}

# --- 3. Leer los registros, con paginación ---
$registros = [System.Collections.Generic.List[object]]::new()
$uri = "$graphBase/$qid/records"
while ($uri) {
    $resp = Invoke-MgGraphRequest -Method GET -Uri $uri
    if ($resp.value) { $registros.AddRange([object[]]$resp.value) }
    $uri = $resp.'@odata.nextLink'
}

Write-Host "Registros obtenidos: $($registros.Count)"
if ($registros.Count -eq 0) {
    Write-Warning 'No se encontraron eliminaciones en el rango indicado. No se generó el CSV.'
    return
}

# --- 4. Exportar ---
$registros | ForEach-Object {
    $audit = $_.auditData
    [PSCustomObject]@{
        Fecha     = $_.createdDateTime
        Usuario   = $_.userPrincipalName
        Operacion = $_.operation
        Archivo   = $audit.SourceFileName
        Ruta      = $_.objectId
        Sitio     = $audit.SiteUrl
        IP        = if ($_.clientIp) { $_.clientIp } else { $audit.ClientIP }
    }
} | Sort-Object Fecha | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Exportado a: $OutputPath"
