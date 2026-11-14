# Auditoría de eliminaciones de usuarios (Microsoft 365)

Script de PowerShell que consulta el **registro de auditoría unificado de Microsoft 365** a través de la API de Microsoft Graph para obtener los archivos y carpetas que un usuario ha eliminado o enviado a la papelera en **SharePoint Online / OneDrive** durante los últimos 30 días. El resultado se exporta a un archivo CSV.

## Qué hace

1. **Crea una consulta de auditoría** (`POST /security/auditLog/queries`) filtrada por:
   - Usuario (UPN).
   - Rango de fechas: los últimos 30 días hasta el momento de ejecución (en UTC).
   - Tipo de registro: `sharePointFileOperation`.
   - Operaciones de eliminación:
     - `FileDeleted`, `FileRecycled`
     - `FileDeletedFirstStageRecycleBin`, `FileDeletedSecondStageRecycleBin`
     - `FolderDeleted`, `FolderRecycled`
2. **Espera a que la consulta termine**, revisando su estado cada 30 segundos mientras esté en `notStarted` o `running`.
3. **Descarga todos los registros**, siguiendo la paginación (`@odata.nextLink`).
4. **Exporta los resultados** a `eliminaciones_graph.csv` en el directorio actual.

## Requisitos

- PowerShell 5.1 o PowerShell 7+.
- Módulo **Microsoft.Graph**:

  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
  ```

- Una cuenta con permiso delegado **`AuditLogsQuery.Read.All`** (requiere consentimiento de administrador) y un rol que permita leer los registros de auditoría (por ejemplo, *Audit Reader* o *Compliance Administrator* en Microsoft Purview).
- La auditoría debe estar habilitada en el tenant.

## Configuración

Antes de ejecutar, edita el script y reemplaza `usuario@dominio.com` por el UPN del usuario a auditar. Aparece en dos lugares:

```powershell
displayName              = "Eliminaciones - usuario@dominio.com"
userPrincipalNameFilters = @("usuario@dominio.com")
```

Opcionalmente puedes ajustar:

| Elemento | Valor por defecto | Cómo cambiarlo |
|---|---|---|
| Rango de fechas | Últimos 30 días | Modifica `.AddDays(-30)` en `filterStartDateTime` |
| Operaciones | Eliminaciones y papelera | Edita la lista `operationFilters` |
| Intervalo de espera | 30 segundos | Modifica `Start-Sleep -Seconds 30` |
| Archivo de salida | `.\eliminaciones_graph.csv` | Cambia la ruta en `Export-Csv` |

## Uso

```powershell
.\auditoria_usuarios.ps1
```

Se abrirá una ventana de inicio de sesión de Microsoft. Tras autenticarte, el script mostrará el ID de la consulta y su estado hasta que finalice. Las consultas de auditoría pueden tardar varios minutos en completarse.

Si la política de ejecución bloquea el script:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Salida

El archivo `eliminaciones_graph.csv` (UTF-8) contiene una fila por evento con las columnas:

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
