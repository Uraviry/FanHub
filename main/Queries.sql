USE FanHub;
GO

-- 1
PRINT 'Generando Reporte 1: Clasificación de Ganancias...';

SELECT
	U.nickname AS Nickname,
	C.nombre AS Categoria,
	(
		SELECT COUNT(*)
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
LEFT JOIN Factura F ON S.id = F.idSuscripcion AND F.fecha_emision >= DATEADD(MONTH, -1, GETDATE())
GROUP BY U.nickname, C.nombre, Cr.idUsuario
ORDER BY [Monto Facturado] DESC;
GO

-- 2
PRINT 'Generando Reporte 2: Viralidad por Categoría...';

WITH MetricasPublicacion AS (
SELECT
	C.nombre AS [Nombre Categoría],
	P.titulo AS [Título Publicación],
	U.nickname AS [Creador],

	CAST (
		((SELECT COUNT(*) FROM UsuarioReaccionPublicacion R WHERE R.idPublicacion = P.id) * 1.5)
		+ ((SELECT COUNT(*) FROM Comentario Com WHERE Com.idPublicacion = P.id) * 3)
		AS DECIMAL(10, 2)
	) AS Puntaje,

	ROW_NUMBER() OVER (
		PARTITION BY C.id
		ORDER BY (
		(SELECT COUNT(*) FROM UsuarioReaccionPublicacion R WHERE R.idPublicacion = P.id) * 1.5
		) + ((SELECT COUNT(*) FROM Comentario Com WHERE Com.idPublicacion = P.id) * 3) DESC
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

-- 3
PRINT 'Generando Reporte 3: Análisis de Dominios de Correo...';

SELECT
	SUBSTRING(email, CHARINDEX('@', email) + 1, LEN(email)) AS Dominio,
	COUNT(*) AS [Cantidad Usuarios]
FROM Usuario
GROUP BY SUBSTRING(email, CHARINDEX('@', email) + 1, LEN(email))
HAVING COUNT(*) > 10
ORDER BY [Cantidad Usuarios] DESC;

-- 4
PRINT 'Generando Reporte 4: Promedio de Retención (Churn)...';

SELECT
	U.nickname AS [Nickname Creador],
	NS.nombre AS [Nombre Nivel],
	AVG(DATEDIFF(day, S.fecha_inicio, S.fecha_fin)) AS [Promedio Días]
FROM Suscripcion S
INNER JOIN NivelSuscripcion NS ON S.idNivel = NS.id
INNER JOIN Usuario U ON NS.idCreador = U.id
WHERE S.estado = 'Cancelada'
GROUP BY U.nickname, NS.nombre, NS.orden
ORDER BY NS.orden ASC;

-- 5
PRINT 'Generando Reporte 5: Tiempo y Peso de Contenido (Gaming)...';

SELECT
	U.nickname,
	CONCAT(SUM(V.duracion_seg) / 3600, 'h ', (SUM(V.duracion_seg) % 3600) / 60, 'm')
	AS [Tiempo Total Formateado],
	SUM(
		CASE
			WHEN V.resolucion = 2160 THEN (V.duracion_seg / 60.0) * 0.5
			WHEN V.resolucion = 1080 THEN (V.duracion_seg / 60.0) * 0.1
			ELSE (V.duracion_seg / 60.0) * 0.05
		END
	) AS [Estimación GB]
FROM Video V
INNER JOIN Publicacion P ON V.idPublicacion = P.id
INNER JOIN Creador Cr ON P.idCreador = Cr.idUsuario
INNER JOIN Usuario U ON Cr.idUsuario = U.id
INNER JOIN Categoria C ON Cr.idCategoria = C.id
WHERE C.nombre = 'Gaming'
GROUP BY U.nickname;

-- 6
PRINT 'Generando Reporte 6: Mapa de Calor Financiero...';

SELECT
	U.pais AS [País],
	SUM(F.monto_total) AS [Total Facturado],
	CONCAT(CAST((SUM(F.monto_total) * 100.0 / (SELECT SUM(monto_total) FROM Factura)) AS DECIMAL(10,1)), '%')
	AS [Share %]
FROM Factura F
INNER JOIN Suscripcion S ON F.idSuscripcion = S.id
INNER JOIN Usuario U ON S.idUsuario = U.id
GROUP BY U.pais
ORDER BY [Total Facturado] DESC;

-- 7
PRINT 'Generando Reporte 7: Intereses Cruzados...';

SELECT
	U.nickname AS [Nickname Usuario],
	SUM(F.monto_total) AS [Gasto Total Histórico]
FROM Usuario U
INNER JOIN Suscripcion S ON U.id = S.idUsuario
INNER JOIN Factura F ON S.id = F.idSuscripcion
INNER JOIN NivelSuscripcion NS ON S.idNivel = NS.id
INNER JOIN Creador Cr ON NS.idCreador = Cr.idUsuario
INNER JOIN Categoria C ON Cr.idCategoria = C.id
WHERE C.nombre IN ('Tecnología', 'Fitness')
GROUP BY U.id, U.nickname
HAVING
	COUNT(DISTINCT C.nombre) = 2 AND
	SUM(F.monto_total) > 140
ORDER BY [Gasto Total Histórico] DESC;

-- 8
PRINT 'Generando Reporte 8: Generaciones...';

SELECT
	CASE
		WHEN YEAR(fecha_nacimiento) > 2000 THEN 'Gen Z'
		WHEN YEAR(fecha_nacimiento) BETWEEN 1981 AND 2000 THEN 'Millennials'
		ELSE 'X'
	END AS [Generación],
	COUNT(DISTINCT U.id) AS [Cantidad Usuarios Activos],
	AVG(Mensual.TotalMes) AS [Gasto Promedio Mensual]
FROM Usuario U
LEFT JOIN (
	SELECT S.idUsuario, SUM(F.monto_total) as TotalMes
	FROM Factura F
	INNER JOIN Suscripcion S ON F.idSuscripcion = S.id
	WHERE F.fecha_emision >= DATEADD(MONTH, -1, GETDATE())
	GROUP BY S.idUsuario
) Mensual ON U.id = Mensual.idUsuario
WHERE U.esta_activo = 1
GROUP BY
	CASE
		WHEN YEAR(fecha_nacimiento) > 2000 THEN 'Gen Z'
		WHEN YEAR(fecha_nacimiento) BETWEEN 1981 AND 2000 THEN 'Millennials'
		ELSE 'X'
	END;

-- 9
PRINT 'Generando Reporte 9: Creadores Polémicos...';

SELECT
	U.nickname,
	COUNT(P.id) AS [Cantidad Posts Evaluados],
	AVG(
		CAST((SELECT COUNT(*) FROM Comentario WHERE idPublicacion = P.id) AS FLOAT) /
		NULLIF((SELECT COUNT(*) FROM UsuarioReaccionPublicacion WHERE idPublicacion = P.id), 0)
	) AS [Ratio Promedio]
FROM Publicacion P
INNER JOIN Usuario U ON P.idCreador = U.id
GROUP BY U.id, U.nickname
HAVING AVG(CAST((SELECT COUNT(*) FROM Comentario WHERE idPublicacion = P.id) AS FLOAT) /
	NULLIF((SELECT COUNT(*) FROM UsuarioReaccionPublicacion WHERE idPublicacion = P.id), 0)) > 2.0;

-- 10
PRINT 'Generando Reporte 10: Ranking de Creadores (Reputación)...';

SELECT
	U.nickname,
	(
		SELECT COUNT(*) FROM Suscripcion S
		INNER JOIN NivelSuscripcion NS ON S.idNivel = NS.id
		WHERE NS.idCreador = Cr.idUsuario AND S.estado = 'Activa'
	) AS [Total Suscriptores],
	dbo.fn_calcular_reputacion(Cr.idUsuario) AS [Puntaje Reputación]
FROM Creador Cr
INNER JOIN Usuario U ON Cr.idUsuario = U.id
WHERE Cr.es_nsfw = 0
AND Cr.idUsuario NOT IN (
	SELECT idCreador FROM Publicacion WHERE tipo_contenido NOT IN ('VIDEO', 'IMAGEN')
)
ORDER BY [Puntaje Reputación] DESC;

-- 11
PRINT 'Generando Reporte 11: Usuarios (Lurkers)...';

SELECT
	U.nickname,
	MAX(S.fecha_inicio) AS [Fecha Última Suscripción],
	SUM(F.monto_total) AS [Monto Gastado (Estimado)]
FROM Usuario U
INNER JOIN Suscripcion S ON U.id = S.idUsuario
LEFT JOIN Factura F ON S.id = F.idSuscripcion
WHERE S.estado = 'Activa'
AND NOT EXISTS (SELECT 1 FROM Comentario WHERE idUsuario = U.id)
AND NOT EXISTS (SELECT 1 FROM UsuarioReaccionPublicacion WHERE idUsuario = U.id)
GROUP BY U.id, U.nickname;

-- 12
PRINT 'Generando Reporte 12: Tendencias (Tags)...';

SELECT TOP 3
	E.nombre AS [Nombre Etiqueta],
	COUNT(PE.idPublicacion) AS [Cantidad Publicaciones]
FROM Etiqueta E
INNER JOIN PublicacionEtiqueta PE ON E.id = PE.idEtiqueta
INNER JOIN Publicacion P ON PE.idPublicacion = P.id
WHERE P.fecha_publicacion >= DATEADD(MONTH, -1, GETDATE())
GROUP BY E.id, E.nombre
ORDER BY [Cantidad Publicaciones] DESC;

-- 13
PRINT 'Generando Reporte 13: Cobertura Total de Reacciones...';

SELECT
	U.nickname,
	COUNT(URP.idTipoReaccion) AS [Total Reacciones Realizadas]
FROM Usuario U
INNER JOIN UsuarioReaccionPublicacion URP ON U.id = URP.idUsuario
GROUP BY U.id, U.nickname
HAVING COUNT(DISTINCT URP.idTipoReaccion) = (SELECT COUNT(*) FROM TipoReaccion);

-- 14
PRINT 'Generando Reporte 14: Reporte de Nómina (Liquidación)...';

SELECT
	Cr.banco_nombre AS [Nombre Banco],
	Cr.banco_cuenta AS [Cuenta Bancaria],
	U.nickname AS Beneficiario,
	SUM(F.monto_total) AS [Total Facturado (Bruto)],
	SUM(F.monto_total) * 0.20 AS [Comisión FanHub],
	SUM(F.monto_total) * 0.80 AS [Monto a Transferir (Neto)]
FROM Factura F
INNER JOIN Suscripcion S ON F.idSuscripcion = S.id
INNER JOIN NivelSuscripcion NS ON S.idNivel = NS.id
INNER JOIN Creador Cr ON NS.idCreador = Cr.idUsuario
INNER JOIN Usuario U ON Cr.idUsuario = U.id
WHERE MONTH(F.fecha_emision) = MONTH(GETDATE()) AND YEAR(F.fecha_emision) = YEAR(GETDATE())
GROUP BY Cr.banco_nombre, Cr.banco_cuenta, U.nickname;
