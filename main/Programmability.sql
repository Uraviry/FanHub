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

        -- Fórmula del puntaje de reputación: (Subs * 0.5) + (Reacciones * 0.1) + (Antigüedad * 2)
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
            THROW; -- Lanza el error hacia arriba
        END CATCH
    END;
    GO

    -- Función para publicar con etiquetas
    CREATE PROCEDURE dbo.sp_publicar_con_etiquetas
    @idCreador INT, @tipo VARCHAR(10), @titulo VARCHAR(128), 
    @es_nsfw BIT, @etiquetas_csv VARCHAR(MAX), @url VARCHAR(255)
    AS
    BEGIN
        SET NOCOUNT ON;
        BEGIN TRY
            BEGIN TRANSACTION;

            -- Insertar Publicación
            INSERT INTO Publicacion (idCreador, tipo_contenido, titulo, fecha_publicacion, es_nsfw, esta_activa)
            VALUES (@idCreador, @tipo, @titulo, GETDATE(), @es_nsfw, 1);

            DECLARE @id INT = SCOPE_IDENTITY();

            -- Insertar en tabla hija según el tipo
            IF @tipo = 'Video'  INSERT INTO Video (idPublicacion, url_stream) VALUES (@id, @url);
            IF @tipo = 'Imagen' INSERT INTO Imagen (idPublicacion, url_imagen) VALUES (@id, @url);
            IF @tipo = 'Texto'  INSERT INTO Texto (idPublicacion, resumen_gratuito) VALUES (@id, @url);

            -- Etiquetas (Insertar nuevas y relacionar)
            INSERT INTO Etiqueta (nombre)
            SELECT DISTINCT value FROM STRING_SPLIT(@etiquetas_csv, ',')
            WHERE value NOT IN (SELECT nombre FROM Etiqueta);

            INSERT INTO PublicacionEtiqueta (idPublicacion, idEtiqueta)
            SELECT @id, e.id FROM Etiqueta e 
            JOIN STRING_SPLIT(@etiquetas_csv, ',') s ON e.nombre = s.value;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
            RAISERROR(@msg, 16, 1);
        END CATCH
    END;
    GO

    -- Falta sp_dashboard_creador y los dos triggers