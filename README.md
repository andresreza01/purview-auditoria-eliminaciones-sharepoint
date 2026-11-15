# Auditoría de eliminaciones de usuarios (Microsoft 365)

Script de PowerShell que consulta el **registro de auditoría unificado de Microsoft 365** a través de la API de Microsoft Graph para obtener los archivos y carpetas que un usuario ha eliminado o enviado a la papelera en **SharePoint Online / OneDrive** durante los últimos 30 días. El resultado se exporta a un archivo CSV.

## Qué hace

1. **Crea una consulta de auditoría** (`POST /security/auditLog/queries`) filtrada por:
   - Usuario o usuarios (UPN).
   - Rango de fechas (por defecto, los últimos 30 días).
   - Tipo de registro: `sharePointFileOperation`.
   - Operaciones de eliminación:
     - `FileDeleted`, `FileRecycled`
     - `FileDeletedFirstStageRecycleBin`, `FileDeletedSecondStageRecycleBin`
     - `FolderDeleted`, `FolderRecycled`
2. **Espera a que la consulta termine**, revisando su estado cada 30 segundos mientras esté en `notStarted` o `running`.
3. **Descarga todos los registros**, siguiendo la paginación (`@odata.nextLink`).
4. **Exporta los resultados** a CSV (por defecto, `eliminaciones_graph.csv` en el directorio actual).

## Requisitos

- PowerShell 5.1 o PowerShell 7+.
- Módulo **Microsoft.Graph**:

  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
  ```

- Una cuenta con permiso delegado **`AuditLogsQuery.Read.All`** (requiere consentimiento de administrador) y un rol que permita leer los registros de auditoría (por ejemplo, *Audit Reader* o *Compliance Administrator* en Microsoft Purview).
- La auditoría debe estar habilitada en el tenant.

## Parámetros

| Parámetro | Obligatorio | Valor por defecto | Descripción |
|---|---|---|---|
| `-UserPrincipalName` | Sí | — | UPN de uno o varios usuarios a auditar |
| `-Days` | No | `30` | Días hacia atrás a consultar (1–180). Se ignora si se indica `-StartDate` |
| `-StartDate` | No | Ahora − `Days` | Inicio del rango |
| `-EndDate` | No | Ahora | Fin del rango |
| `-OutputPath` | No | `.\eliminaciones_graph.csv` | Ruta del CSV de salida |
| `-PollSeconds` | No | `30` | Segundos entre comprobaciones del estado de la consulta |
| `-TimeoutMinutes` | No | `60` | Tiempo máximo de espera antes de abortar |

La ayuda completa está disponible con `Get-Help .\auditoria_usuarios.ps1 -Full`.

## Uso

```powershell
# Un usuario, últimos 30 días
.\auditoria_usuarios.ps1 -UserPrincipalName usuario@dominio.com

# Varios usuarios, últimos 7 días, salida personalizada
.\auditoria_usuarios.ps1 -UserPrincipalName a@dominio.com, b@dominio.com -Days 7 -OutputPath C:\Temp\eliminaciones.csv

# Rango de fechas concreto
.\auditoria_usuarios.ps1 -UserPrincipalName usuario@dominio.com -StartDate 2026-10-01 -EndDate 2026-10-31
```

Si no hay una sesión de Microsoft Graph activa con el permiso necesario, se abrirá una ventana de inicio de sesión; si ya existe, se reutiliza. El script mostrará el ID de la consulta y su estado hasta que finalice. Las consultas de auditoría pueden tardar varios minutos en completarse.

El script se detiene con un error si la consulta falla o se cancela, o si supera `-TimeoutMinutes`. Si no hay resultados, muestra un aviso y no genera el CSV.

Si la política de ejecución bloquea el script:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Salida

El archivo CSV (UTF-8) contiene una fila por evento, ordenadas por fecha, con las columnas:

| Columna | Descripción |
|---|---|
| `Fecha` | Fecha y hora del evento (UTC) |
| `Usuario` | UPN del usuario que realizó la acción |
| `Operacion` | Tipo de operación (p. ej. `FileRecycled`) |
| `Archivo` | Nombre del archivo o carpeta afectada |
| `Ruta` | URL completa del objeto |
| `Sitio` | URL del sitio de SharePoint / OneDrive |
| `IP` | Dirección IP del cliente |

## Notas

- Los eventos de auditoría pueden tardar en aparecer en el registro (normalmente entre 30 minutos y 24 horas).
- El periodo de retención de la auditoría depende de la licencia (180 días en Audit Standard por defecto).
- Para cerrar la sesión de Graph al terminar: `Disconnect-MgGraph`.

## Referencias

- [API de consultas de auditoría (Microsoft Graph)](https://learn.microsoft.com/graph/api/resources/security-auditlogquery)
- [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/powershell/microsoftgraph/overview)
