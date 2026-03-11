USE FanHub;
GO
-- Funciones UDF
    -- Función para calcular el impuesto (IVA 16%)
    CREATE FUNCTION dbo.fn_calcular_impuesto (@monto DECIMAL(10,2))
    RETURNS DECIMAL(10,2)
    AS
    BEGIN
        RETURN @monto * 0.16;
    END;
    GO

    -- Función para clasificar al creador según su ingreso
    CREATE FUNCTION dbo.fn_clasificar_ingreso (@monto DECIMAL(10,2))
    RETURNS NVARCHAR(20)
    AS
    BEGIN
        DECLARE @resultado NVARCHAR(20);
        IF @monto > 1000 SET @resultado = 'Diamante';
        ELSE IF @monto BETWEEN 500 AND 1000 SET @resultado = 'Oro';
        ELSE SET @resultado = 'Plata';
        
        RETURN @resultado;
    END;
    GO

    -- Función para calcular la reputación de un creador
    CREATE FUNCTION dbo.fn_calcular_reputacion (@idCreador INT)
    RETURNS DECIMAL(5,2)
    AS
    BEGIN
        -- Declaración de variables
        DECLARE @puntaje DECIMAL(10,2) = 0;
        DECLARE @subsActivos INT;
        DECLARE @reaccionesMes INT;
        DECLARE @antiguedadMeses INT;

        -- Total Suscriptores Activos
        SELECT @subsActivos = COUNT(*) 
        FROM Suscripcion s
        JOIN NivelSuscripcion ns ON s.idNivel = ns.id
        WHERE ns.idCreador = @idCreador AND s.estado = 'Activa';

        -- Total Reacciones Último Mes
        SELECT @reaccionesMes = COUNT(*)
        FROM UsuarioReaccionPublicacion urp
        JOIN Publicacion p ON urp.idPublicacion = p.id
        WHERE p.idCreador = @idCreador 
        AND urp.fecha_reaccion >= DATEADD(month, -1, GETDATE());

        -- Antigüedad en Meses
        SELECT @antiguedadMeses = DATEDIFF(month, fecha_registro, GETDATE())
        FROM Usuario
        WHERE id = @idCreador;

        -- Fórmula del puntaje de reputación
        SET @puntaje = (@subsActivos * 0.5) + (@reaccionesMes * 0.1) + (@antiguedadMeses * 2);

        -- Tope máximo de 100
        IF @puntaje > 100 SET @puntaje = 100;

        RETURN @puntaje;
    END;
    GO

-- Funciones SP
    -- Función para generar factura
    CREATE PROCEDURE dbo.sp_generar_factura
    @idSuscripcion INT,
    @montoBase DECIMAL(10,2)
    AS
    BEGIN
        DECLARE @impuesto DECIMAL(10,2) = dbo.fn_calcular_impuesto(@montoBase);
        DECLARE @total DECIMAL(10,2) = @montoBase + @impuesto;
        
        -- Variables para el código de transacción
        DECLARE @idUsuario INT, @idNivel INT, @idCreador INT;
        SELECT @idUsuario = idUsuario, @idNivel = idNivel FROM Suscripcion WHERE id = @idSuscripcion;
        SELECT @idCreador = idCreador FROM NivelSuscripcion WHERE id = @idNivel;

        INSERT INTO Factura (idSuscripcion, codigo_transaccion, fecha_emision, sub_total, monto_impuesto, monto_total)
        VALUES (
            @idSuscripcion,
            CONCAT(FORMAT(GETDATE(), 'yyyyMMdd'), '-', @idUsuario, '-', @idSuscripcion, '-', @idNivel, '-', @idCreador),
            GETDATE(),
            @montoBase,
            @impuesto,
            @total
        );
    END;
    GO

    -- Función para crear una suscripción
    CREATE PROCEDURE dbo.sp_crear_suscripcion
    @idUsuario INT,
    @idNivel INT,
    @idMetodoPago INT
    AS
    BEGIN
        SET NOCOUNT ON;
        DECLARE @precioActual DECIMAL(10,2), @idNuevaSub INT;

        SELECT @precioActual = precio_actual FROM NivelSuscripcion WHERE id = @idNivel;

        BEGIN TRY
            -- Validación para saber si el usuario ya está suscrito a este nivel
            IF EXISTS (
                SELECT 1 FROM Suscripcion 
                WHERE idUsuario = @idUsuario 
                  AND idNivel = @idNivel 
                  AND estado = 'Activa'
            )
            BEGIN
                RAISERROR('Ya tiene una suscripción activa para este nivel.', 16, 1);
                RETURN; -- Con este return sale del procedimiento sin hacer nada
            END

            BEGIN TRANSACTION;

            -- Crear suscripción
            INSERT INTO Suscripcion (idUsuario, idNivel, fecha_inicio, fecha_renovacion, estado, precio_pactado)
            VALUES (@idUsuario, @idNivel, GETDATE(), DATEADD(month, 1, GETDATE()), 'Activa', @precioActual);

            SET @idNuevaSub = SCOPE_IDENTITY();

            -- Llama a la función de facturación
            EXEC dbo.sp_generar_factura @idNuevaSub, @precioActual;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; -- Si hubo error, deshace la suscripción y la factura
            THROW;
        END CATCH
    END;
    GO

    -- Función para publicar con etiquetas
    CREATE PROCEDURE dbo.sp_publicar_con_etiquetas
    @idCreador INT, 
    @tipo VARCHAR(10), 
    @titulo VARCHAR(128), 
    @es_publica BIT,
    @etiquetas_publicacion VARCHAR(MAX), 
    @url VARCHAR(255)
    AS
    BEGIN
        SET NOCOUNT ON;
        BEGIN TRY
            BEGIN TRANSACTION;

            -- Insertar Publicación
            INSERT INTO Publicacion (idCreador, titulo, fecha_publicacion, es_publica, tipo_contenido)
            VALUES (@idCreador, @titulo, GETDATE(), @es_publica, UPPER(@tipo));

            DECLARE @id INT = SCOPE_IDENTITY();

            -- Insertar en tabla hija según el tipo
            IF @tipo = 'Video'  INSERT INTO Video (idPublicacion, url_stream) VALUES (@id, @url);
            IF @tipo = 'Imagen' INSERT INTO Imagen (idPublicacion, url_imagen) VALUES (@id, @url);
            IF @tipo = 'Texto'  INSERT INTO Texto (idPublicacion, resumen_gratuito) VALUES (@id, @url);

            -- Etiquetas
            INSERT INTO Etiqueta (nombre)
            SELECT DISTINCT value FROM STRING_SPLIT(@etiquetas_publicacion, ',')
            WHERE value NOT IN (SELECT nombre FROM Etiqueta);

            INSERT INTO PublicacionEtiqueta (idPublicacion, idEtiqueta)
            SELECT @id, e.id FROM Etiqueta e 
            JOIN STRING_SPLIT(@etiquetas_publicacion, ',') s ON e.nombre = s.value;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            THROW; 
        END CATCH
    END;
    GO

    CREATE PROCEDURE dbo.sp_dashboard_creador
    @idCreador INT,
    @fecha_inicio DATE,
    @fecha_fin DATE
    AS
    BEGIN
        SET NOCOUNT ON;
        BEGIN TRY
            -- Dinero y Suscriptores
            SELECT 
                ISNULL(SUM(f.monto_total), 0) AS ingresos_totales,
                COUNT(s.id) AS nuevos_suscriptores
            FROM Suscripcion s
            JOIN NivelSuscripcion ns ON s.idNivel = ns.id
            LEFT JOIN Factura f ON f.idSuscripcion = s.id
            WHERE ns.idCreador = @idCreador 
            AND s.fecha_inicio BETWEEN @fecha_inicio AND @fecha_fin;

            -- Top 5 fans
            SELECT TOP 5 u.nickname, SUM(conteo) AS total_interacciones
            FROM (
                -- Cuenta comentarios del creador
                SELECT idUsuario, COUNT(*) AS conteo FROM Comentario c
                JOIN Publicacion p ON c.idPublicacion = p.id WHERE p.idCreador = @idCreador GROUP BY idUsuario
                UNION ALL
                -- Cuenta reacciones del creador
                SELECT idUsuario, COUNT(*) AS conteo FROM UsuarioReaccionPublicacion urp
                JOIN Publicacion p ON urp.idPublicacion = p.id WHERE p.idCreador = @idCreador GROUP BY idUsuario
            ) AS resumen
            JOIN Usuario u ON resumen.idUsuario = u.id
            GROUP BY u.nickname
            ORDER BY total_interacciones DESC;

            -- Publicación con más puntos
            SELECT TOP 1 
                p.titulo,
                ( (SELECT COUNT(*) FROM UsuarioReaccionPublicacion WHERE idPublicacion = p.id) * 1.5 + 
                (SELECT COUNT(*) FROM Comentario WHERE idPublicacion = p.id) * 3 ) AS puntaje_viralidad
            FROM Publicacion p
            WHERE p.idCreador = @idCreador 
            AND p.fecha_publicacion BETWEEN @fecha_inicio AND @fecha_fin
            ORDER BY puntaje_viralidad DESC;

        END TRY
        BEGIN CATCH
            THROW; 
        END CATCH
    END;
    GO

-- Triggers

    -- Validación de aumento de precio
    CREATE TRIGGER tr_validar_aumento_precio
    ON NivelSuscripcion
    AFTER UPDATE
    AS
    BEGIN
        SET NOCOUNT ON;

        -- Verifica si la columna precio_actual fue la que cambió
        IF UPDATE(precio_actual)
        BEGIN
            -- Se compara el precio nuevo con el viejo
            IF EXISTS (
                SELECT 1 
                FROM inserted i 
                JOIN deleted d ON i.id = d.id
                WHERE i.precio_actual > (d.precio_actual * 1.50)
            )
            BEGIN
                RAISERROR('Operación cancelada: No se permite aumentar el precio más del 50%% de una sola vez.', 16, 1);
                ROLLBACK TRANSACTION; -- Esto deshace el UPDATE
            END
        END
    END;
    GO

    -- Validación de edad para contenido NSFW
    CREATE TRIGGER tr_validar_edad_nsfw
    ON Suscripcion
    AFTER INSERT
    AS
    BEGIN
        SET NOCOUNT ON;

        IF EXISTS (
            SELECT 1 
            FROM inserted i
            JOIN NivelSuscripcion ns ON i.idNivel = ns.id
            JOIN Creador c ON ns.idCreador = c.idUsuario
            JOIN Usuario u ON i.idUsuario = u.id
            WHERE c.es_nsfw = 1 
            AND DATEDIFF(YEAR, u.fecha_nacimiento, GETDATE()) < 18
        )
        BEGIN
            RAISERROR('Contenido restringido: Debes ser mayor de 18 años para suscribirte a este creador.', 16, 1);
            ROLLBACK TRANSACTION; -- Evita que la suscripción se guarde
        END
    END;
    GO