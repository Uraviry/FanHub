USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = 'FanHub')
BEGIN
    ALTER DATABASE FanHub SET SINGLE_USER WITH ROLLBACK IMMEDIATE; 
    DROP DATABASE FanHub;
END
GO

CREATE DATABASE FanHub;
GO

USE FanHub;
GO

DROP TABLE IF EXISTS PublicacionEtiqueta;
DROP TABLE IF EXISTS PublicacionEtiqueta;
DROP TABLE IF EXISTS Etiqueta;
DROP TABLE IF EXISTS UsuarioReaccionPublicacion;
DROP TABLE IF EXISTS TipoReaccion;
DROP TABLE IF EXISTS Comentario;
DROP TABLE IF EXISTS Imagen;
DROP TABLE IF EXISTS Texto;
DROP TABLE IF EXISTS Video;
DROP TABLE IF EXISTS Publicacion;
DROP TABLE IF EXISTS Factura;
DROP TABLE IF EXISTS Suscripcion;
DROP TABLE IF EXISTS NivelSuscripcion;
DROP TABLE IF EXISTS MetodoPago;
DROP TABLE IF EXISTS Creador;
DROP TABLE IF EXISTS Categoria;
DROP TABLE IF EXISTS Usuario;

CREATE TABLE Usuario
(
	id 			INT IDENTITY(1,1) PRIMARY KEY,
	email 			VARCHAR(64),
	password_hash 		VARCHAR(255) NOT NULL,
	nickname 		VARCHAR(32) NOT NULL UNIQUE,
	fecha_registro DATE DEFAULT GETDATE(),
	fecha_nacimiento DATE CHECK (fecha_nacimiento <= DATEADD(year, -13, GETDATE())),
	pais 			VARCHAR(2),
	esta_activo 		BIT DEFAULT 1
);

CREATE TABLE Categoria
(
	id 			INT IDENTITY(1,1) PRIMARY KEY,
	nombre 			VARCHAR(32),
	descripcion 		TEXT
);

CREATE TABLE Creador
(
	idUsuario 		INT PRIMARY KEY REFERENCES Usuario(id),
	biografia 		TEXT,
	banco_nombre 		VARCHAR(64),
	banco_cuenta 		NUMERIC(20, 0),
	es_nsfw 		BIT,
	idCategoria 		INT REFERENCES Categoria(id)
);

CREATE TABLE MetodoPago
(
	id 			INT IDENTITY(1,1) PRIMARY KEY,
	idUsuario 		INT REFERENCES Usuario(id),
	ultimos_4_digitos 	NUMERIC(4, 0),
	marca 			VARCHAR(32),
	titular 		VARCHAR(64),
	fecha_expiracion 	DATE,
	es_predeterminado 	BIT
);

CREATE TABLE NivelSuscripcion
(
	id 			INT IDENTITY(1,1) PRIMARY KEY,
	idCreador 		INT REFERENCES Creador(idUsuario),
	nombre 			VARCHAR(32),
	descripcion 		TEXT,
	precio_actual 		DECIMAL(10, 2) CHECK (precio_actual >= 0),
	esta_activo 		BIT,
	orden 			INTEGER
);

CREATE TABLE Suscripcion
(
	id 			INT IDENTITY(1,1) PRIMARY KEY,
	idUsuario 		INT REFERENCES Usuario(id),
	idNivel 		INT REFERENCES NivelSuscripcion(id),
	fecha_inicio 		DATE,
	fecha_renovacion 	DATE,
	fecha_fin 		DATE,
	estado 			VARCHAR(9) CHECK (estado IN ('Activa', 'Cancelada', 'Vencida')),
	precio_pactado 		DECIMAL(10, 2) CHECK (precio_pactado >= 0)
);

CREATE TABLE Factura
(
	id 			INT IDENTITY(1,1) PRIMARY KEY,
	idSuscripcion 		INT REFERENCES Suscripcion(id),
	codigo_transaccion 	VARCHAR(64),
	fecha_emision 		DATE,
	sub_total 		DECIMAL(10, 2) CHECK (sub_total >= 0),
	monto_impuesto 		DECIMAL(10, 2) CHECK (monto_impuesto >= 0),
	monto_total 		DECIMAL(10, 2) CHECK (monto_total >= 0)
);

CREATE TABLE Publicacion
(
	id 			INT IDENTITY(1,1) PRIMARY KEY,
	idCreador 		INT REFERENCES Creador(idUsuario),
	titulo 			VARCHAR(128),
	fecha_publicacion 	DATE,
	es_publica 		BIT,
	tipo_contenido 		VARCHAR(6) CHECK (tipo_contenido IN ('VIDEO', 'TEXTO', 'IMAGEN'))
); 

CREATE TABLE Video
(
	idPublicacion 		INT PRIMARY KEY REFERENCES Publicacion(id),
	duracion_seg 		INTEGER,
	resolucion 		INTEGER CHECK(resolucion IN(720,1080,2160)),
	url_stream 		VARCHAR(255)
); 

CREATE TABLE Texto
(
	idPublicacion 		INT PRIMARY KEY REFERENCES Publicacion(id),
	contenido_html 		TEXT,
	resumen_gratuito 	VARCHAR(1024)
);

CREATE TABLE Imagen
(
	idPublicacion 	INT PRIMARY KEY REFERENCES Publicacion(id),
	ancho 			INTEGER,
	alto 			INTEGER,
	formato 		VARCHAR(10),
	alt_text 		VARCHAR(128),
	url_imagen 		VARCHAR(255)
);

CREATE TABLE Comentario
(
	id 			INT IDENTITY(1,1) PRIMARY KEY,
	idUsuario 		INT REFERENCES Usuario(id),
	idPublicacion 		INT REFERENCES Publicacion(id),
	idComentarioPadre 	INT REFERENCES Comentario(id),
	texto 			TEXT NOT NULL,
	fecha 			DATETIME DEFAULT GETDATE()
);

CREATE TABLE TipoReaccion
(
	id 			INT IDENTITY(1,1) PRIMARY KEY,
	nombre 			VARCHAR(32),
	emoji_code 		NVARCHAR(32)
);

CREATE TABLE UsuarioReaccionPublicacion
(
	idUsuario 		INT REFERENCES Usuario(id),
	idPublicacion 		INT REFERENCES Publicacion(id),
	idTipoReaccion 		INT REFERENCES TipoReaccion(id),
	fecha_reaccion 		DATE DEFAULT GETDATE(),
	PRIMARY KEY (idUsuario, idPublicacion)
);
 
CREATE TABLE Etiqueta
(
	id 			INT IDENTITY(1,1) PRIMARY KEY,
	nombre 			VARCHAR(32)
);
 
CREATE TABLE PublicacionEtiqueta
(
	idPublicacion 		INT REFERENCES Publicacion(id),
	idEtiqueta 		INT REFERENCES Etiqueta(id),
	PRIMARY KEY (idPublicacion, idEtiqueta)
);