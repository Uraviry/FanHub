USE FanHub;
GO

-- 1
PRINT 'Generando Reporte 1: Clasificación de Ganancias...';

SELECT 
    U.nickname AS Nickname,
    C.nombre AS Categoria,
    (SELECT COUNT(*) 
     FROM Suscripcion S 
     INNER JOIN NivelSuscripcion NS ON S.idNivel = NS.id
     WHERE NS.idCreador = Cr.idUsuario AND S.estado = 'Activa'
    ) AS [Total Suscriptores Activos],
    ISNULL(SUM(F.monto_total), 0) AS [Monto Facturado],
    dbo.fn_clasificar_ingreso(ISNULL(SUM(F.monto_total), 0)) AS [Clasificación]
FROM Usuario U
INNER JOIN Creador Cr ON U.id = Cr.idUsuario
INNER JOIN Categoria C ON Cr.idCategoria = C.id
LEFT JOIN NivelSuscripcion NS ON Cr.idUsuario = NS.idCreador
LEFT JOIN Suscripcion S ON NS.id = S.idNivel
LEFT JOIN Factura F ON S.id = F.idSuscripcion 
    AND F.fecha_emision >= DATEADD(MONTH, -1, GETDATE())
GROUP BY 
    U.nickname, 
    C.nombre, 
    Cr.idUsuario
ORDER BY [Monto Facturado] DESC;
GO


-- 2. 
PRINT 'Generando Reporte 2: Viralidad por Categoría...';

WITH MetricasPublicacion AS (
    SELECT 
        C.nombre AS [Nombre Categoría],
        P.titulo AS [Título Publicación],
        U.nickname AS [Creador],

        CAST(
            ((SELECT COUNT(*) FROM UsuarioReaccionPublicacion R WHERE R.idPublicacion = P.id) * 1.5) +
            ((SELECT COUNT(*) FROM Comentario Com WHERE Com.idPublicacion = P.id) * 3) 
        AS DECIMAL(10,2)) AS Puntaje,

        ROW_NUMBER() OVER (
            PARTITION BY C.id 
            ORDER BY ((SELECT COUNT(*) FROM UsuarioReaccionPublicacion R WHERE R.idPublicacion = P.id) * 1.5) +
                     ((SELECT COUNT(*) FROM Comentario Com WHERE Com.idPublicacion = P.id) * 3) DESC
        ) AS Ranking
    FROM Publicacion P
    INNER JOIN Creador Cr ON P.idCreador = Cr.idUsuario
    INNER JOIN Usuario U ON Cr.idUsuario = U.id
    INNER JOIN Categoria C ON Cr.idCategoria = C.id
)
SELECT 
    [Nombre Categoría],
    [Título Publicación],
    [Creador],
    Puntaje AS [Puntaje Máximo]
FROM MetricasPublicacion
WHERE Ranking = 1
ORDER BY [Puntaje Máximo] DESC;
GO

