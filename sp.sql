USE [FICS.ERSA]
GO
/****** Object:  StoredProcedure [dbo].[Pasaje_GetPrinterInfoXML]    Script Date: 6/28/2023 5:11:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[Pasaje_GetPrinterInfoXML]
( 
 @Pasaje int,
 @Operacion int,
 @retval varchar(8000) OUTPUT
)						
 AS
 SET NOCOUNT ON
--4.17
 DECLARE @TRAFICONIVEL_LINEA TINYINT = 1, @TRAFICONIVEL_RECORRIDO TINYINT = 2, @TRAFICONIVEL_SERVICIO TINYINT = 3, @TRAFICONIVEL_VIAJE TINYINT = 4
 --Conexiones
 declare @ConexionOrden tinyint
 if @Operacion=0 and (select top 1 1 from Venta_Conexiones_Pasajes with(nolock) where PasajeID=@Pasaje)=1
 begin
	declare @ConexionID int
	select top 1 @ConexionOrden=Orden, @ConexionID=(select ConexionID from Venta_Conexiones VC with(nolock) where VC.VentaConexionID=VCP.VentaConexionID) from Venta_Conexiones_Pasajes VCP with(nolock) where PasajeID=@Pasaje
	if (@ConexionOrden=1 and (select ImpresionServicio from TFC_ServiciosConexiones with(nolock) where ServicioConexionID=@ConexionID)=0) or 
		(@ConexionOrden=2 and (select ImpresionConexion from TFC_ServiciosConexiones with(nolock) where ServicioConexionID=@ConexionID)=0)
	begin
		select @retval=''
		return
	end
 end

-- ***************************************************************************************
-- BUSCO PARAMETROS DE LA VENTA DE PASAJES
-- ***************************************************************************************

declare @CS_RedondeaCifras tinyint
declare @CS_CantidadDecimales smallint
declare @CS_BarCodeType smallint
DECLARE @CS_IVARestriccion tinyint
DECLARE @CS_IVARestriccionSobre tinyint
declare @CS_Percepciones_Cobro int, @CS_Percepciones_Devolucion int, @CS_MicroseguroConcepto int
SELECT @CS_CantidadDecimales = NULL
declare @Moneda varchar(10), @MonedaLiteral varchar(50), @NumeroComprobanteDevolucion varchar(50)

SELECT	@CS_RedondeaCifras=ConfigXML.value('data(/XML/ventas/@redondea)[1]','smallint'), 
		@CS_CantidadDecimales=ConfigXML.value('data(/XML/general/@cifrasRedondeo)[1]','smallint'),
		@CS_BarCodeType=ConfigXML.value('data(/XML/general/@fuenteCodigoBarra)[1]','smallint'),
		@CS_IVARestriccion=ConfigXML.value('data(/XML/impuestos/@aplicaRestricciones)[1]','tinyint'),
		@CS_IVARestriccionSobre=ConfigXML.value('data(/XML/impuestos/@aplicaRestriccionesSobreGraban)[1]','tinyint'),
		@CS_Percepciones_Cobro=isnull(ConfigXML.value('data(/XML/contabilidad/@percepcionCobro)[1]','int'),0),
		@CS_Percepciones_Devolucion=isnull(ConfigXML.value('data(/XML/contabilidad/@percepcionDevolucion)[1]','int'),0),
		@CS_MicroseguroConcepto=isnull(ConfigXML.value('data(/XML/contabilidad/@microseguroCobro)[1]','int'),0)
from configuraciones with(nolock)
where Type=9 and Owner=0

/* DEPRECADO [TKT 36877]
declare @CS_Abonos_FechaTope tinyint
declare @CS_Abonos_Imprime tinyint
SELECT	
		@CS_Abonos_FechaTope=ConfigXML.value('data(/XML/abonos/@vigenciaDias)[1]','tinyint'),
		@CS_Abonos_Imprime=ConfigXML.value('data(/XML/abonos/@imprimeComprobante)[1]','tinyint')
from configuraciones with(nolock)
where Type=9 and Owner=0
*/

IF @CS_CantidadDecimales IS NULL		SELECT @CS_CantidadDecimales = 2
IF @CS_BarCodeType IS NULL		SELECT @CS_BarCodeType =-1


DECLARE @paisBoleteria int, @DireccionBoleteria varchar(200), @BoleteriaId int , @provinciaBoleteria int, @TelefonoBoleteria varchar(25), @PasajeOperacionVentaId int, @poVentaFechaOperacion datetime
SELECT @BoleteriaId=Boleteria FROM dbo.PasajesOperaciones WITH(NOLOCK) WHERE Pasaje =@Pasaje AND Operacion IN(0, 13)
SELECT @paisBoleteria =(select P.PaisId from dbo.G_Regiones P WITH(NOLOCK) where P.RegionId =L.RegionId), @provinciaBoleteria =L.RegionId, @TelefonoBoleteria=Telefonos
FROM dbo.Boleterias B WITH(NOLOCK) INNER JOIN dbo.G_Localidades L WITH(NOLOCK) ON L.LocalidadId =B.LocalidadID 
WHERE B.Id = @BoleteriaId


if @Operacion != 0
begin
	select @PasajeOperacionVentaId = dbo.Pasaje_GetPasajeOperacionOriginal(@Pasaje, 0)
	select @poVentaFechaOperacion = fechaOperacion from PasajesOperaciones with(nolock) where id = @PasajeOperacionVentaId
end

select @DireccionBoleteria=isnull(calle, '') + ' ' + isnull(nullif(CAST(numero as varchar), '0'), '') + ' ' + isnull(nullif(cast(piso as varchar), 0), '') from g_direccionesOwners with(nolock)
inner join g_direcciones with(nolock) on g_direcciones.direccionId = g_direccionesOwners.direccionId
where ownerId = @BoleteriaId and direccionTipo = 1 and ownerType = 3


--------- DECLARACION DE VARIABLES
DECLARE @OPERACION_VENTA tinyint
DECLARE @OPERACION_EMISION_CANJE tinyint
DECLARE @OPERACION_ANULACION tinyint
DECLARE @OPERACION_REIMPRESION_COMPROBANTE int
DECLARE @OPERACION_DEVOLUCION tinyint
DECLARE @OPERACION_DEJARABIERTO tinyint
DECLARE @OPERACION_CAMBIOFECHA tinyint
DECLARE @OPERACION_PAGARCONBOLETO tinyint
DECLARE @OPERACION_MULTAPAGARCONBOLETO tinyint

SELECT @OPERACION_VENTA = 0
SELECT @OPERACION_EMISION_CANJE = 13
SELECT @OPERACION_ANULACION=1
SELECT @OPERACION_REIMPRESION_COMPROBANTE = -1
SELECT @OPERACION_DEVOLUCION = 2
SELECT @OPERACION_DEJARABIERTO = 5
SELECT @OPERACION_CAMBIOFECHA = 4
SELECT @OPERACION_PAGARCONBOLETO = 16
SELECT @OPERACION_MULTAPAGARCONBOLETO = 15
declare @pNumero varchar(20)
declare @pBarCode varchar(100)
declare @pEmpresa smallint
declare @eEmpresaCUIT varchar(20)
declare @pLocalidadOrigen int
declare @pTerminalOrigen int
declare @pLocalidadDestino int
declare @pTerminalDestino int
declare @pViaje int
declare @pViajeEtiqueta varchar(10)
declare @pFechaPartida datetime
declare @pHoraPartida tinyint
declare @FechaPartidaSTRAMPM varchar(25)
declare @servicioNombre varchar(50)
declare @servicioDescripcion varchar(500)
declare @PorcInteres varchar(4)
declare @ImpInteres money
declare @pButaca varchar(30)
declare @nroOrdenFormacion varchar(30)
declare @pTarifaBase money
declare @pImporteDescuentos money
declare @pImporteTotal money
declare @TotalConExcesoEquipaje money = 0
declare @pPasajeTipo int
declare @pPersona int
declare @pFechaTope datetime
declare @pCaja int
declare @pMedioPago int
declare @pMedioPagoTipo tinyint
declare @pIdaVuelta smallint
declare @pMedioPagoCuotas smallint
declare @vCoche int
declare @vLinea smallint
declare @vTerminalDestino int
declare @vCategoria smallint
declare @vRecorrido int
declare @cocheNombre varchar(20)
declare @cocheMatricula varchar(20)
declare @lineaNombre varchar(10)
declare @pasajeTipoNombre varchar(30)
declare @pMedioPagoNombre varchar(30)
declare @pasajeTipoPorcentage smallmoney
DECLARE @pasajeTipoTipoDescRgo tinyint
declare @pasajeTipoAplicaA tinyint
declare @pasajeTipoImporte money
declare @categoriaServicioNombre varchar(20)
declare @categoriaTarifaNombre varchar(20)
declare @poBoleteria smallint
declare @poUsuario int
declare @poFechaOperacion datetime
declare @poIVAAlicuota smallmoney
declare @poIVAImporte money
declare @poImporteOperacion money
DECLARE @OmegConex varchar (200) = 'Conexión a: '
declare @poMonedaID smallint
declare @poCaja int
declare @personaDocumento varchar(20)
declare @personaDocumentoTipo varchar(10)
declare @personaNombre varchar(20)
declare @personaApellido varchar(20)
declare @personaApellidoNombre varchar(40)
declare @personaDocumentoTipoINT tinyint
declare @personaFechaNacimiento datetime
declare @personaFechaNacimientoSTR varchar(12)
declare @personaDomicilio varchar(200)
declare @personaSexo tinyint
declare @personaSexoSTR varchar(10)
declare @PasajeComentario varchar(500)
declare @Comentario varchar(500)
declare @Comentario2 varchar(500)
declare @Comentario3 varchar(500)
declare @Comentario4 varchar(500)
declare @ComprAnulacion varchar(25)
declare @Conexion char(8)
select @Comentario = '',@Comentario2='',@Comentario3='',@Comentario4=''
declare @ViajeDespachoID int
declare @RegulacionID int
declare @RegulacionBasisCode varchar(10)
declare @ClaseTarifaria varchar(30)
declare @DiferenciaTarifaria varchar(20)
declare @MicroSeguroLabel varchar(50)
declare @MicroSeguroImporte money
declare @strMicroSeguroImporte varchar(50)
declare @CodigoConfigSTR varchar(100)
declare @CodigoConfigXML xml

declare @SinServicioAbordo varchar (20)

DECLARE @EMP_IngresosBrutos varchar(20)
DECLARE @EMP_InicioActividad varchar(20)
DECLARE @BOL_InicioActividad varchar(20)

DECLARE @personaTipoCNRT char

declare @ComentarioNegrita varchar(500)

declare @personaProfesionSTR varchar(20)
declare @personaProfesion int

declare @FechaHoraPartidaSTR varchar(30)
declare @Nacionalidad varchar(80)
declare @NacionalidadID int
declare @Voucher varchar(5)

declare @Servicio int
declare @ServicioCodigo varchar(20)
DECLARE @CategoriaS int
DECLARE @ServicioKGPermitidos varchar(20)
SELECT @ServicioKGPermitidos = ''
DECLARE @ServicioEquipajePermitido varchar(20)
declare @ImporteExcesoEquipaje money
declare @ImporteBaseDolares money

declare @PaisOrigen int, @PaisDestino int, @ComentarioInter varchar(500)

declare @TransportadorSTR varchar(30)
declare @BoleteriaSTR varchar(30)
declare @BoleteriaCodigoSTR varchar(10)
declare @BoleteriaDireccionSTR varchar(500)
declare @BoleteriaCUITSTR varchar(20)
declare @BoleteriaTelefonoSTR varchar(500)
declare @LocalidadOrigenSTR varchar(50)
declare @TerminalOrigenSTR varchar(50)
declare @TerminalDestinoSTR varchar(50)
declare @LocalidadOrigenETSTR varchar(10)
declare @LocalidadDestinoSTR varchar(50)
declare @LocalidadDestinoETSTR varchar(10)
declare @UsuarioCodigoSTR varchar(20)
declare @UsuarioNombreSTR varchar(50)
declare @UsuarioNombreCortoSTR varchar (20)
declare @FechaPartidaSTR varchar(10)
declare @FechaPartidaFullYearSTR varchar(10)
declare @FechaPartidaLiteral varchar(40)
declare @FechaArriboSTR varchar(10)
declare @HoraPartidaSTR varchar(10)
declare @HoraPartidaSTRAMPM varchar(20)
declare @HoraArribo varchar(6)
declare @PasajeEstadoSTR varchar(50)
declare @SeAnunciaSTR varchar(70)
declare @SeAnunciaLocalidadSTR varchar(70)
declare @SeguroValor money
declare @SeguroTipo tinyint
declare @SeguroImporte money = 0
declare @PasajeCosto money
declare @SeguroCotizacionIndice float
declare @vTipo tinyint
declare @vDestino int
declare @ServicioSTR varchar(15)
declare @Comprobante varchar(20)
declare @CtaCte_Empresa varchar(50)
declare @CtaCte_Empresa_CUIT varchar(50)
declare @CtaCte_EmpresaID int
declare @Multa varchar(30)
declare @MultaSTR varchar(30)
declare @PF_PuntosCanjeados int, @PF_SaldoPuntos int
declare @FechaPartidaAnio varchar(4), @FechaPartidaMes varchar(2), @FechaPartidaDia varchar(2), @FechaArriboAnio varchar(4), @FechaArriboMes varchar(2), @FechaArriboDia varchar(2), @FechaOperacionAnio varchar(4), @FechaOperacionMes varchar(2), @FechaOperacionDia varchar(2)
DECLARE @PersonaTelefono varchar(20)
DECLARE @BoleteriaAutorizada varchar(50)
DECLARE @BoleteriaAutorizadaSTR varchar(15)
declare @AbonoNro varchar(15)
declare @pFechaArribo datetime
declare @vTipoLinea tinyint
declare @vTipoLineaNombre varchar(15)
declare @Coche varchar(15)
declare @tipoVenta varchar(15)
declare @ETT int
declare @ETT_TarifaIda money, @ETT_TarifaIdaVuelta money, @ETT_TarifaDiferencia money
declare @PasajeCanje varchar(100)
declare @PasajeCanjeTarifaBase varchar(20)
declare @PasajeCanjeTarifaFinal varchar(20)
declare @pCanjeNumero varchar(15)
DECLARE @PF_Puntos varchar(20)
DECLARE @PF_PuntosSTR varchar(20)
DECLARE @CNOR_SERVICIO_PUBLICO TINYINT
DECLARE @CNOR_SERVICIO_EJECUTIVO TINYINT
DECLARE @CNOR_SERVICIO_COMUNcAIRE TINYINT
declare @pPercepciones money, @ImporteTotalSPercepcion money
declare @strPercepciones varchar(50)
SET @CNOR_SERVICIO_PUBLICO = 9
SET @CNOR_SERVICIO_EJECUTIVO = 2
SET @CNOR_SERVICIO_COMUNcAIRE = 1
declare @TarjSinDev varchar(500)

DECLARE @PAP_DESTINO varchar (200)
DECLARE @PAP_ORIGEN varchar (200)
DECLARE @PAP_ORIGENENTRE varchar (200)
DECLARE @PAP_DESTINOENTRE varchar (200)
declare @TerminalOrigenIsPAP tinyint
declare @TerminalDestinoIsPAP tinyint

DECLARE @Telefono_Empresa varchar (20)

DECLARE @MEDIOPAGOTIPO_CTACTE TINYINT
SELECT @MEDIOPAGOTIPO_CTACTE = 3

DECLARE @ETT_NOMBRE varchar(50)

DECLARE @PublicoX CHAR
DECLARE @EjecutivoX CHAR
DECLARE @ComunCaX CHAR
DECLARE @TalonarioInicial int, @TalonarioFinal int, @CodigoAutorizacion varchar(100), @TalonarioSerie varchar(5), @RangoTalonario varchar(50), @TalonarioVencimiento varchar(10)

SET @PublicoX = ''
SET @EjecutivoX = ''
SET @ComunCaX = ''

declare @pHoraPresentacion varchar(25)

declare @ConnectorNombre varchar(50), @ConnectorBoleto varchar(20)

DECLARE @ImporteTotaDevolucion money
DECLARE @ImporteRetencion money
DECLARE @PorcentajeRetencion int

declare @Comentario1 varchar(500)
declare @Comentario6 varchar(500)
declare @Comentario7 varchar(500)
declare @Comentario8 varchar(500)

declare @SIdayVuelta varchar(100)
declare @Departure varchar(100)
------------------------------------------------------
set @pCanjeNumero = ''
set @PasajeCanje = ''
set @personaDocumentoTipo='Doc Nro:'
set @personaDocumento=''
set @personaNombre=''
set @personaApellido=''
declare @Pais smallint
set @cocheNombre=''


DECLARE @TerminalTelefonoOrigen varchar (20)
DECLARE @TerminalTelefonoDestino varchar (20)
DECLARE @TerminalDireccionOrigen varchar (250)
DECLARE @TerminalDireccionDestino varchar (250)

SELECT	@pNumero =Numero, @pEmpresa =Empresa, @pViaje =Viaje, @pLocalidadOrigen =LocalidadOrigen, @pTerminalOrigen =TerminalOrigen, 
	@pLocalidadDestino =LocalidadDestino, @pImporteTotal =ImporteFinal,@pTerminalDestino =TerminalDestino, @pTarifaBase =ImporteBase, 
	@pImporteDescuentos =ImporteDescuentos, @pPasajeTipo =TipoPasaje , @pPersona =Persona, @pFechaTope =viajeFechaTope, @ETT =EsquemaTarifarioTarifa,
	@RegulacionID = EsquemaTarifarioRegulacionID
FROM 	dbo.Pasajes WITH(NOLOCK) WHERE id =@Pasaje

select @pPercepciones=dbo.Pasaje_GetPercepcionesFunction(@Pasaje, @CS_Percepciones_Cobro, @CS_Percepciones_Devolucion)
select @ImporteTotalSPercepcion = @pImporteTotal
select @pImporteTotal=@pImporteTotal+@pPercepciones

select @strPercepciones = cast(@pPercepciones as varchar(50))
IF DB_NAME() in ('WF_COPE', 'WF_COPE_TEST') select @strPercepciones = cast(cast(@pPercepciones as int) as varchar(50))

set @pImporteDescuentos=@pImporteDescuentos * -1

-- Manejo de los Codigos de Barra
IF @pNumero IS NOT NULL
BEGIN
	DECLARE @DummyPasajeNumero varchar(100)
	DECLARE @DummyPasajeSerie varchar(3) 
	IF @CS_BarCodeType =1
	BEGIN
		SET @DummyPasajeSerie = SUBSTRING(RTRIM(@pNumero), 0, 4)
		SET @DummyPasajeNumero = SUBSTRING(RTRIM(@pNumero), 5, LEN(RTRIM(@pNumero)))
		SET @DummyPasajeNumero = REPLICATE('0', (9 - LEN(@DummyPasajeNumero)))+@DummyPasajeNumero
		SET @DummyPasajeNumero = @DummyPasajeSerie+@DummyPasajeNumero
	END
	ELSE
		SET @DummyPasajeNumero =RTRIM(@pNumero)

	SET @pBarCode = dbo.BarCode_TransformString(@DummyPasajeNumero, @CS_BarCodeType)
END
ELSE 
	SET @pBarCode = ''
	
--REGULACIONES
select @RegulacionBasisCode = ''
select @ClaseTarifaria = ''
if @RegulacionID > 0 and @RegulacionID is not null
begin
	select @RegulacionBasisCode = BasisCode,
	@ClaseTarifaria=(select Nombre from TFC_CategoriasServiciosClasesTarifarias csct with(nolock) where csct.CategoriaServicioClaseTarifariaID = r.CategoriaServicioClaseTarifariaID)
	from EsquemasTarifariosRegulaciones r with(nolock)
	where r.EsquemaTarifarioRegulacionID=@RegulacionID
end

declare @poID int
declare @EsPagarConBoleto tinyint
select @EsPagarConBoleto = 0
if (exists(select top 1 1 from PasajesOperaciones with(nolock) where Pasaje = @Pasaje and Operacion = @OPERACION_MULTAPAGARCONBOLETO)) select @EsPagarConBoleto = 1

--raiserror('PCB %i, Pasaje %i',16,1,@espagarconboleto, @pasaje)return

IF @Operacion = @OPERACION_REIMPRESION_COMPROBANTE OR @Operacion = @OPERACION_CAMBIOFECHA or @EsPagarConBoleto = 1 OR @Operacion = @OPERACION_DEJARABIERTO
BEGIN
	IF @Operacion = @OPERACION_CAMBIOFECHA or @EsPagarConBoleto = 1 OR @Operacion = @OPERACION_DEJARABIERTO OR @Operacion = @OPERACION_REIMPRESION_COMPROBANTE
	BEGIN
		SELECT @MultaSTR = 'Multa'
	 IF EXISTS (SELECT 1 FROM Pasajes_Canjes WITH (NOLOCK) WHERE PasajeGeneradoID=@Pasaje) AND @EsPagarConBoleto = 0
				SELECT @Multa = CAST(ImporteOperacion as varchar(30)) FROM PasajesOperaciones WITH (NOLOCK) INNER JOIN Pasajes_Canjes WITH (NOLOCK) ON Pasajes_Canjes.PasajeCanjeadoID = PasajesOperaciones.Pasaje WHERE Pasajes_Canjes.PasajeGeneradoID = @Pasaje AND Operacion in (@OPERACION_CAMBIOFECHA, @OPERACION_MULTAPAGARCONBOLETO,@OPERACION_REIMPRESION_COMPROBANTE, @OPERACION_DEJARABIERTO)
	 ELSE 
				SELECT @Multa = CAST(ImporteOperacion as varchar(30)) FROM PasajesOperaciones WITH (NOLOCK) WHERE Pasaje = @Pasaje AND Operacion in (@OPERACION_CAMBIOFECHA, @OPERACION_MULTAPAGARCONBOLETO, @OPERACION_DEJARABIERTO,@OPERACION_REIMPRESION_COMPROBANTE)
		IF @Multa IS NULL SET @Multa = 0
	END
	
	SELECT @poID = dbo.Pasaje_GetPasajeOperacionOriginal(@Pasaje, @OPERACION_EMISION_CANJE)
	IF @poID IS NULL
		SELECT @poID = dbo.Pasaje_GetPasajeOperacionOriginal(@Pasaje, @OPERACION_VENTA)
END
ELSE
BEGIN
	IF @Operacion = @OPERACION_VENTA
	BEGIN
		SELECT @poID = dbo.Pasaje_GetPasajeOperacionOriginal(@Pasaje, @OPERACION_EMISION_CANJE)
		IF @poID IS NULL
			SELECT @poID = dbo.Pasaje_GetPasajeOperacionOriginal(@Pasaje, @OPERACION_VENTA)
	END
	ELSE
		SELECT @poID = dbo.Pasaje_GetPasajeOperacionOriginal(@Pasaje, @Operacion)
END



SELECT 	@poImporteOperacion=ImporteOperacion, @poBoleteria=boleteria, @poUsuario=Usuario, @poFechaOperacion=fechaoperacion, 
	@poIVAAlicuota=IVAAlicuota, @poIVAImporte=IVAImporte, @Comprobante =MedioPagoComprobante, @poCaja=ISNULL(CajaUsuario,0), @poMonedaID = MonedaID,
	@pMedioPago = MedioPago, @pMedioPagoCuotas=MedioPagoCuotas
FROM dbo.PasajesOperaciones WITH(NOLOCK) 
WHERE Id = @poID

select @Moneda=Simbolo, @MonedaLiteral=Nombre from monedas with(nolock) where id = @poMonedaID

if db_name() = 'WF_OLTR'
begin
	select top 1 @poFechaOperacion=fechaoperacion from PasajesOperaciones WITH(NOLOCK) where pasaje = @Pasaje order by id desc
end

select @Servicio=servicio, @vTerminalDestino=terminalDestino from viajes WITH(NOLOCK)where viajes.id=@pViaje
select @ServicioCodigo = codigo from servicios with(nolock) where id = @Servicio
select @servicioNombre = Nombre FROM Servicios WHERE ID = @Servicio
select @servicioDescripcion = (SELECT Texto FROM Comentarios WHERE Tipo = 19 and Owner =(SELECT ID FROM Servicios WHERE ID = @Servicio))

select @Voucher=UPPER(Comprobante) From Pasajes_Vouchers WITH(NOLOCK) WHERE Pasaje=@Pasaje
IF @Voucher IS NULL SET @Voucher = ''

select @MicroSeguroImporte = importeOperacion from PasajesOperaciones with(nolock) where ETConceptoOp = @CS_MicroseguroConcepto and Pasaje = @Pasaje
if @MicroSeguroImporte is not null
begin
	select @MicroSeguroLabel = 'Micro seguro'
	select @pImporteTotal = @pImporteTotal + @MicroSeguroImporte
end

--VARIABLE PARA EL IMPORTE DE EXCESO DE EQUIPAJE
SELECT @ImporteExcesoEquipaje = SUM(ImporteFinal) FROM Pasajes_ExcesosEquipaje WHERE PasajeID = @Pasaje
select @TotalConExcesoEquipaje = @pImporteTotal + isnull(@ImporteExcesoEquipaje, 0)

select @strMicroSeguroImporte = cast(@MicroSeguroImporte as varchar(50))
IF DB_NAME() in ('WF_COPE', 'WF_COPE_TEST') select @strMicroSeguroImporte = cast(cast(@MicroSeguroImporte as int) as varchar(50))


if @CS_RedondeaCifras=1
begin
	set @poIVAImporte=round(@poIVAImporte, @CS_CantidadDecimales)
	set @pTarifaBase=round(@pTarifaBase, @CS_CantidadDecimales)
	set @pImporteDescuentos=round(@pImporteDescuentos, @CS_CantidadDecimales)
	set @pImporteTotal=round(@pImporteTotal, @CS_CantidadDecimales)
	set @TotalConExcesoEquipaje = ROUND(@TotalConExcesoEquipaje, @CS_CantidadDecimales)
	set @MicroSeguroImporte = ROUND(@MicroSeguroImporte, @CS_CantidadDecimales)
end



if @pViaje IS NOT NULL
begin
	if exists (select 1 from viajesbutacas WITH(NOLOCK)where pasaje=@pasaje)
	begin
		select @pButaca=Butaca from viajesbutacas WITH(NOLOCK)where pasaje=@Pasaje
		select @nroOrdenFormacion=NroOrdenFormacion from viajesbutacas WITH(NOLOCK)where pasaje=@Pasaje
	end
	else
	begin
		set @pButaca='PP'
		set @nroOrdenFormacion='S/A'
	end
	select @vCoche=coche, @vLinea=Linea, @vCategoria=Categoria,@vRecorrido = recorrido from viajes WITH(NOLOCK)where id=@pViaje
	SELECT @categoriaServicioNombre =Nombre FROM categoriasServicios WITH(NOLOCK) WHERE id =@vCategoria
	select @cocheNombre=''		
	if @vCoche IS NOT NULL
		
		select @cocheNombre=Nombre, @cocheMatricula=isnull(Matricula,'') from coches WITH(NOLOCK)where id=@vCoche
		
	else	
		select @cocheNombre=' ', @cocheMatricula=''
	select @lineaNombre=Nombre from lineas WITH(NOLOCK)where id=@vLinea

	select @pFechaPartida=FechaPartida from viajesrecorridos WITH(NOLOCK)where viaje=@pViaje and Terminal=@pTerminalOrigen
	select @FechaPartidaSTRAMPM = convert(varchar (25), @pFechaPartida, 0)
	select @pFechaArribo=fechaArribo from viajesrecorridos WITH(NOLOCK)where viaje=@pViaje and Terminal=@pTerminalDestino
	
	SELECT @vCategoria =Categoria, @ETT_TarifaIda = Precio_OneWay, @ETT_TarifaIdaVuelta=Precio_RoundTrip, @ETT_TarifaDiferencia= Precio_OneWay - Precio_RoundTrip FROM dbo.EsquemasTarifariosTarifas WITH(NOLOCK) WHERE id =@ETT	
	SELECT @categoriaTarifaNombre =Nombre FROM categoriasServicios WITH(NOLOCK) WHERE id =@vCategoria

	IF @vCategoria = @CNOR_SERVICIO_PUBLICO SELECT @PublicoX = 'X'
	IF @vCategoria = @CNOR_SERVICIO_EJECUTIVO SELECT @EjecutivoX = 'X'
	IF @vCategoria = @CNOR_SERVICIO_COMUNcAIRE SELECT @ComunCaX = 'X'

	---Armo la fecha de partida del viaje en literal

	declare @dp varchar (15)
	select @dp= datename ( weekday , @pFechaPartida) 


	if @dp='Monday'
		set @dp='Lunes'
	
	if @dp='Tuesday'
		set @dp='Martes'
	
	if @dp='Wednesday'
		set @dp='Miercoles'
	
	if @dp='Thursday '
		set @dp='Jueves'
	
	if @dp='Friday'
		set @dp='Viernes'
	
	if @dp='Saturday'
		set @dp='Sabado'
	
	if @dp='Sunday'
		set @dp='Domingo'
	

	declare @mp varchar (15)
	select @mp= datename ( month , @pFechaPartida) 

	if @mp='January'
		set @mp='Enero'
	if @mp='February'
		set @mp='Febrero'
	if @mp='March'
		set @mp='Marzo'
	if @mp='April'
		set @mp='Abril'
	if @mp='May'
		set @mp='Mayo'
	if @mp='June'
		set @mp='Junio'
	if @mp='July'
		set @mp='Julio'
	if @mp='August'
		set @mp='Agosto'
	if @mp='September'
		set @mp='Septiembre'
	if @mp='October'
		set @mp='Octubre'
	if @mp='November'
		set @mp='Noviembre'
	if @mp='December'
		set @mp='Diciembre'

	if db_name() in ('WF_BTEL')
	begin
		--EN BETEL APARECE VIERNES 01-01-2000 01:01
		SELECT @FechaPartidaLiteral = @dp + ' ' + (case when day(@pFechaPartida) < 10 then '0' else '' end) + cast(day(@pFechaPartida) as varchar(5)) + '-' + (case when month(@pFechaPartida) < 10 then '0' else '' end) + cast(month(@pFechaPartida) as varchar(5)) + '-' + cast(year(@pFechaPartida) as varchar(5)) + ' ' + case when datepart(hh, @pFechaPartida) < 10 then '0' else '' end + cast(datepart(hh, @pFechaPartida) as varchar(2)) + ':' + case when datepart(mi, @pFechaPartida) < 10 then '0' else '' end + cast(datepart(mi, @pFechaPartida) as varchar(2))
	end
	else
	begin
		--EN EL RESTO APARECE VIERNES 1 DE ENERO DE 2000
		SELECT @FechaPartidaLiteral=(@dp + ' ' + cast(DATEPART(dd, @pFechaPartida) as varchar(3)) + ' ' + 'de' + ' ' + @mp + ' ' + 'de' + ' ' + cast(DATEPART(yyyy, @pFechaPartida) as varchar(5)) ) 
	end
	if db_name() in ('WF_SING')
	begin
		--EN SINGER APARECE 01/01/2000 VIERNES
		SELECT @FechaPartidaLiteral = (case when day(@pFechaPartida) < 10 then '0' else '' end) + cast(day(@pFechaPartida) as varchar(5)) + '/' + (case when month(@pFechaPartida) < 10 then '0' else '' end) + cast(month(@pFechaPartida) as varchar(5)) + '/' + cast(year(@pFechaPartida) as varchar(5)) + ' ' + @dp
	end
	if db_name() in ('WF_SLVA')
	begin
		--EN SILVIA APARECE VIE 01/01/2000
		SELECT @FechaPartidaLiteral = substring(@dp,0,3)+ ' ' + (case when day(@pFechaPartida) < 10 then '0' else '' end) + cast(day(@pFechaPartida) as varchar(5)) + '/' + (case when month(@pFechaPartida) < 10 then '0' else '' end) + cast(month(@pFechaPartida) as varchar(5)) + '/' + cast(year(@pFechaPartida) as varchar(5))
	end
	if db_name() = 'WF_TCNI'
	begin
		if @Servicio =8 and @pLocalidadOrigen=15251
			set @SeAnunciaSTR = 'Pasaje en combinacion origen Tierra Del Fuego'

		if @Servicio =9 and @pLocalidadDestino=15251
			set @SeAnunciaSTR = 'Pasaje en combinacion destino Tierra Del Fuego'
	END



end
else 
begin
	SELECT @vCategoria =Categoria, @ETT_TarifaIda = Precio_OneWay, @ETT_TarifaIdaVuelta=Precio_RoundTrip, @ETT_TarifaDiferencia= Precio_OneWay - Precio_RoundTrip FROM dbo.EsquemasTarifariosTarifas WITH(NOLOCK) WHERE id =@ETT
	SELECT @pButaca ='**'
	SELECT @nroOrdenFormacion = '**'
	SELECT @categoriaServicioNombre =Nombre FROM categoriasServicios WITH(NOLOCK) WHERE id =@vCategoria
	SELECT @categoriaTarifaNombre =Nombre FROM categoriasServicios WITH(NOLOCK) WHERE id =@vCategoria
	SELECT @lineaNombre =''
	SELECT @FechaPartidaLiteral=''
	
	if db_name() in ('WF_CMTR', 'WF_CMTR_TEST')
			BEGIN

				set @tipoVenta=''
				set @Comentario = 'Boleto con Fecha Abierta'
				set @Comentario2='No Válido Para Viajar'
			
			END


end


/* **** Seguro resolucion 684 **** */
	SELECT Top 1 @SeguroTipo = ET_Seguros.ValorTipo, @SeguroValor = ET_Seguros.Valor
	FROM ET_Seguros 
	WHERE	
			ET_Seguros.VigenciaDesde <= @poFechaOperacion
	and		ET_Seguros.VigenciaHasta > @poFechaOperacion
	AND		ET_Seguros.MonedaID = @poMonedaID
	AND		ET_Seguros.EmpresaID = @pEmpresa
	AND		(ET_Seguros.ServicioCategoriaID is null or ET_Seguros.ServicioCategoriaID = @vCategoria)
	AND		ET_Seguros.ValorDesde <= @poImporteOperacion
	AND		(
				NOT EXISTS(select top 1 1 from ET_Seguros_NivelTrafico with(nolock) where ET_Seguros_NivelTrafico.SeguroID = ET_Seguros.SeguroID)
			OR
				exists(select top 1 1 from ET_Seguros_NivelTrafico with(nolock) where ET_Seguros_NivelTrafico.SeguroID = ET_Seguros.SeguroID and ET_Seguros_NivelTrafico.OwnerType = @TRAFICONIVEL_LINEA and ET_Seguros_NivelTrafico.OwnerID = @vLinea)
			OR
				exists(select top 1 1 from ET_Seguros_NivelTrafico with(nolock) where ET_Seguros_NivelTrafico.SeguroID = ET_Seguros.SeguroID and ET_Seguros_NivelTrafico.OwnerType = @TRAFICONIVEL_RECORRIDO and ET_Seguros_NivelTrafico.OwnerID = @vRecorrido)
			OR
				exists(select top 1 1 from ET_Seguros_NivelTrafico with(nolock) where ET_Seguros_NivelTrafico.SeguroID = ET_Seguros.SeguroID and ET_Seguros_NivelTrafico.OwnerType = @TRAFICONIVEL_SERVICIO and ET_Seguros_NivelTrafico.OwnerID = @Servicio)
			OR
				exists(select top 1 1 from ET_Seguros_NivelTrafico with(nolock) where ET_Seguros_NivelTrafico.SeguroID = ET_Seguros.SeguroID and ET_Seguros_NivelTrafico.OwnerType = @TRAFICONIVEL_VIAJE and ET_Seguros_NivelTrafico.OwnerID = @pViaje)	
	)
	AND		(
				NOT EXISTS(select top 1 1 from ET_Seguros_Tramos with(nolock) where ET_Seguros_Tramos.SeguroID = ET_Seguros.SeguroID)
			OR
				exists(select top 1 1 from ET_Seguros_Tramos with(nolock) where ET_Seguros_Tramos.SeguroID = ET_Seguros.SeguroID AND ET_Seguros_Tramos.TerminalOrigenID = @pTerminalOrigen and ET_Seguros_Tramos.TerminalDestinoID = @pTerminalDestino)
	)

	ORDER BY ET_Seguros.ServicioCategoriaID desc,
		case when exists(select top 1 1 from ET_Seguros_Tramos with(nolock) where ET_Seguros_Tramos.SeguroID = ET_Seguros.SeguroID AND ET_Seguros_Tramos.TerminalOrigenID = @pTerminalOrigen and ET_Seguros_Tramos.TerminalDestinoID = @pTerminalDestino) then 1
			else 2 end,
		case 
			when exists(select top 1 1 from ET_Seguros_NivelTrafico with(nolock) where ET_Seguros_NivelTrafico.SeguroID = ET_Seguros.SeguroID and ET_Seguros_NivelTrafico.OwnerType = @TRAFICONIVEL_VIAJE and ET_Seguros_NivelTrafico.OwnerID = @pViaje)	 then 1
			when exists(select top 1 1 from ET_Seguros_NivelTrafico with(nolock) where ET_Seguros_NivelTrafico.SeguroID = ET_Seguros.SeguroID and ET_Seguros_NivelTrafico.OwnerType = @TRAFICONIVEL_SERVICIO and ET_Seguros_NivelTrafico.OwnerID = @Servicio) then 2
			when exists(select top 1 1 from ET_Seguros_NivelTrafico with(nolock) where ET_Seguros_NivelTrafico.SeguroID = ET_Seguros.SeguroID and ET_Seguros_NivelTrafico.OwnerType = @TRAFICONIVEL_RECORRIDO and ET_Seguros_NivelTrafico.OwnerID = @vRecorrido) then 3
			when exists(select top 1 1 from ET_Seguros_NivelTrafico with(nolock) where ET_Seguros_NivelTrafico.SeguroID = ET_Seguros.SeguroID and ET_Seguros_NivelTrafico.OwnerType = @TRAFICONIVEL_LINEA and ET_Seguros_NivelTrafico.OwnerID = @vLinea) then 4
		end


if @SeguroTipo is not null and @SeguroValor is not null
begin
	select @SeguroImporte = @SeguroValor
	if @SeguroTipo = 1 /*PORCENTAJE*/
	begin
		select @SeguroImporte = @SeguroValor / 100 * @pImporteTotal
	end
end
select @PasajeCosto = @pImporteTotal - isnull(@SeguroImporte, 0)
/* **** /Seguro resolucion 684 **** */

select @pasajeTipoNombre=Nombre, @pasajeTipoTipoDescRgo=TipoDescRgo, @pasajeTipoAplicaA =aplicaA from pasajestipos WITH(NOLOCK)where id=@pPasajeTipo
select @pMedioPagoTipo=tipo, @pMedioPagoNombre=Nombre from mediosPago with(nolock) where id = @pMedioPago

SET @pasajeTipoPorcentage=0
SET @pasajeTipoImporte=0
IF @pasajeTipoTipoDescRgo = 1
	select @pasajeTipoPorcentage = importe from pasajestipos WITH(NOLOCK)where id=@pPasajeTipo
IF @pasajeTipoTipoDescRgo = 2
	select @pasajeTipoImporte = importe from pasajestipos WITH(NOLOCK)where id=@pPasajeTipo


/* DEPRECADO [TKT 36877]
set @AbonoNro =''
IF @pasajeTipoAplicaA =1 --ES UN ABONO!!!
BEGIN
	SELECT @AbonoNro = ISNULL(Abonos.PlantillaNumero,CAST(Abonos.AbonoId AS VARCHAR))
	FROM dbo.Abonos WITH(NOLOCK)INNER JOIN dbo.AbonosPasajes WITH(NOLOCK) ON dbo.Abonos.AbonoID =dbo.AbonosPasajes.AbonoID
		WHERE dbo.AbonosPasajes.pasajeId =@Pasaje
END
*/


select @TransportadorSTR=Nombre, @eEmpresaCUIT=isnull(CUIT, '') , @Telefono_Empresa = Telefonos
from empresastransportadoras WITH(NOLOCK)
where id=ISNULL((SELECT Empresa FROM Viajes WITH(NOLOCK) WHERE Id=@pViaje), @pEmpresa)

select @BoleteriaSTR=Nombre, @BoleteriaCodigoSTR=Codigo, @BoleteriaCUITSTR = CUIT from boleterias WITH(NOLOCK)where id=@poBoleteria

select @BoleteriaDireccionSTR = 
isnull((select nombre + ' ' from G_Localidades L with(nolock) where L.LocalidadId = D.LocalidadId), '') + 
isnull(D.Calle + ' ', '') + 
isnull(cast(numero as varchar),'')
from g_direcciones D with(nolock)
inner join g_direccionesOwners DO with(nolock) on D.DireccionId = DO.DireccionId
where DO.DireccionTipo = 1 and DO.OwnerType = 3 and DO.OwnerId = @poBoleteria

select @TerminalOrigenIsPAP=isPAP, @TerminalOrigenSTR=Nombre from terminales WITH(NOLOCK)where id=@pTerminalOrigen
select @TerminalDestinoIsPAP=isPAP,@TerminalDestinoSTR=Nombre from terminales WITH(NOLOCK)where id=@pTerminalDestino



select @LocalidadOrigenSTR=G_Localidades.Nombre, @PaisOrigen=G_Regiones.PaisID from G_Localidades WITH(NOLOCK) inner join G_Regiones with(nolock) on G_Localidades.RegionId=G_Regiones.RegionId where G_Localidades.LocalidadId=@pLocalidadOrigen
select @LocalidadOrigenETSTR=Nombre from LocalidadesEmpresasTransportadoras WITH(NOLOCK)where localidad=@pLocalidadOrigen and empresa=@pEmpresa
select @LocalidadDestinoSTR=G_Localidades.Nombre, @PaisDestino=G_Regiones.PaisID from G_Localidades WITH(NOLOCK) inner join G_Regiones with(nolock) on G_Localidades.RegionId=G_Regiones.RegionId where G_Localidades.LocalidadId=@pLocalidadDestino
select @LocalidadDestinoETSTR=Nombre from LocalidadesEmpresasTransportadoras WITH(NOLOCK)where localidad=@pLocalidadDestino and empresa=@pEmpresa

select @ComentarioInter = ''
if @PaisOrigen != @PaisDestino
begin
	select @ComentarioInter = 'Presentarse en Plataforma de Embarque 01:30 Hs. antes de la partida para realizar Control Aduanero y evitar demoras o perdida del servicio.'
end

select @UsuarioCodigoSTR=Codigo, @UsuarioNombreSTR=Nombre, @UsuarioNombreCortoSTR=NombreCorto from usuarios WITH(NOLOCK)where id=@poUsuario

-- Si el pasaje se genero por canje muestra los puntos q se invirtieron en el canje
if exists(select 1 from pf_canjes with(nolock) where TargetType=0 and TargetID=@Pasaje)
	select @PF_PuntosCanjeados = PuntosCanjeados
	from pf_canjes with(nolock) 
	where TargetType=0 and TargetID=@Pasaje

-- Si el pasaje sumo puntos. se muestra los puntos q sumo.
if exists(select 1 from pf_puntos with(nolock) where TargetType=0 and TargetID=@Pasaje)
	select @PF_PuntosCanjeados = KMSaldo
	from pf_puntos with(nolock) 
	where TargetType=0 and TargetID=@Pasaje



if @pViaje IS NOT NULL
begin
	set @tipoVenta=''
	select @vTipo=TipoViaje, @vDestino=LocalidadDestino, @vTipoLinea =tipolinea from viajes WITH(NOLOCK)where id=@pViaje
	select @SeAnunciaSTR=SeAnunciaDestino from Servicios WITH(NOLOCK)where id=@Servicio

	
	IF EXISTS (SELECT 1 FROM dbo.TFC_TerminalesDiferenciasHorarias WITH (NOLOCK) WHERE TerminalID =@pTerminalOrigen)
		SELECT @pFechaPartida =DATEADD(hh, (SELECT DiferenciaHoras FROM dbo.TFC_TerminalesDiferenciasHorarias WITH (NOLOCK) WHERE TerminalID =@pTerminalOrigen), @pFechaPartida)
	IF EXISTS (SELECT 1 FROM dbo.TFC_TerminalesDiferenciasHorarias WITH (NOLOCK) WHERE TerminalID =@pTerminalDestino)
		SELECT @pFechaArribo =DATEADD(hh, (SELECT DiferenciaHoras FROM dbo.TFC_TerminalesDiferenciasHorarias WITH (NOLOCK) WHERE TerminalID =@pTerminalDestino), @pFechaArribo)


	set @FechaPartidaSTR = convert(varchar(30), @pFechaPartida, 3)
	set @FechaPartidaFullYearSTR = convert(varchar(30), @pFechaPartida, 103)
	set @FechaArriboSTR = convert(varchar(30), @pFechaArribo, 3)
	set @pHoraPartida = DatePart(hh,@pFechaPartida)
	if Len(DatePart(mi,@pFechaPartida)) = 0
	begin
		if DB_NAME() IN ('WF_FLAM', 'WF_CTRA') set @HoraPartidaSTRAMPM = cast((case when @pHoraPartida > 12 then @pHoraPartida - 12 else @pHoraPartida end) as varchar(2)) + ':00' + (case when @pHoraPartida > 12 then ' pm' else ' am' end)
		set @HoraPartidaSTR = cast(DatePart(hh,@pFechaPartida) as varchar(2)) + ':00'
	end
	
	if Len(DatePart(mi,@pFechaPartida)) = 1
	begin
		if DB_NAME() IN ('WF_FLAM', 'WF_CTRA') set @HoraPartidaSTRAMPM = cast((case when @pHoraPartida > 12 then @pHoraPartida - 12 else @pHoraPartida end) as varchar(2)) + ':0' + cast(DatePart(mi,@pFechaPartida) as varchar(2)) + (case when @pHoraPartida > 12 then ' pm' else ' am' end)
		set @HoraPartidaSTR = cast(DatePart(hh,@pFechaPartida) as varchar(2)) + ':0' + cast(DatePart(mi,@pFechaPartida) as varchar(2))
	end
	else
	begin
		if DB_NAME() IN ('WF_FLAM', 'WF_CTRA') set @HoraPartidaSTRAMPM = cast((case when @pHoraPartida > 12 then @pHoraPartida - 12 else @pHoraPartida end) as varchar(2)) + ':' + cast(DatePart(mi,@pFechaPartida) as varchar(2)) + (case when @pHoraPartida > 12 then ' pm' else ' am' end)
		set @HoraPartidaSTR = cast(DatePart(hh,@pFechaPartida) as varchar(2)) + ':' + cast(DatePart(mi,@pFechaPartida) as varchar(2))
	end	
	if DB_NAME() = 'WF_FLAM' and (case when @pHoraPartida > 12 then @pHoraPartida - 12 else @pHoraPartida end) < 10 select @HoraPartidaSTR = '0' + @HoraPartidaSTR

 if Len(DatePart(mi,@pFechaArribo)) = 0
	begin
		set @HoraArribo = cast(DatePart(hh,@pFechaArribo) as varchar(2)) + ':00'
	end
	
	if Len(DatePart(mi,@pFechaArribo)) = 1
	begin
		set @HoraArribo = cast(DatePart(hh,@pFechaArribo) as varchar(2)) + ':0' + cast(DatePart(mi,@pFechaArribo) as varchar(2))
	end
	else
	begin
		set @HoraArribo = cast(DatePart(hh,@pFechaArribo) as varchar(2)) + ':' + cast(DatePart(mi,@pFechaArribo) as varchar(2))
	end
	
	--set @HoraPartidaSTR = cast(DatePart(hh,@pFechaPartida) as varchar(2)) + ':' + cast(DatePart(mi,@pFechaPartida) as varchar(2))
	SET @FechaHoraPartidaSTR = @FechaPartidaSTR+' '+@HoraPartidaSTR
	if DB_NAME() IN ('WF_FLAM', 'WF_CTRA')
	begin
		if (DatePart(HH,@pFechaPartida) >= 0 and DatePart(HH,@pFechaPartida) < 10) or (DatePart(HH,@pFechaPartida) - 12 >= 0 and DatePart(HH,@pFechaPartida) - 12 < 10) select @HoraPartidaSTRAMPM = '0' + @HoraPartidaSTRAMPM
		set @HoraPartidaSTR = @HoraPartidaSTRAMPM
	end	
	set @PasajeEstadoSTR = ''
	set @SeAnunciaLocalidadSTR = ISNULL(@SeAnunciaSTR, '')
	set @SeAnunciaSTR = 'Se anuncia a: ' + @SeAnunciaSTR 
	--set @HoraArribo =cast(DatePart(hh,@pFechaArribo) as varchar(2)) + ':' + cast(DatePart(mi,@pFechaArribo) as varchar(2))
	if @vTipoLinea =1 Set @vTipoLineaNombre ='Provincial'
	else if @vTipoLinea =2 Set @vTipoLineaNombre ='Nacional'
	else Set @vTipoLineaNombre ='Internacinal'
	
	IF DB_NAME() = 'WF_NSDA'
	BEGIN
		SELECT @CategoriaS= categoria FROM Viajes WITH(NOLOCK)WHERE Viajes.Id=@pViaje 

		IF @CategoriaS IN(1, 2)
			SET @ServicioEquipajePermitido='1 BOLSO 1 DE MANO'
			
		ELSE
			SET @ServicioEquipajePermitido='2 BOLSOS 1 DE MANO'
		SET @ServicioKGPermitidos='30 KG Máximo Permitido'	
	END
END
ELSE
BEGIN
	set @pButaca='**'	
	set @nroOrdenFormacion='**'
	set @cocheNombre='Abierto'
	set @tipoVenta='Abierto'
	SET @ServicioEquipajePermitido=' '
	SET @ServicioKGPermitidos=' '
	set @FechaPartidaSTR = '**/**/**'
	SET @FechaArriboSTR = '**/**/**'
	set @HoraArribo = '**:**'
	set @HoraPartidaSTR = '**:**'
	SET @FechaHoraPartidaSTR = @FechaPartidaSTR+' '+@HoraPartidaSTR		
	set @PasajeEstadoSTR = '** FECHA ABIERTA **'

	if(@Operacion = @OPERACION_VENTA)
	begin
		if @pasajeTipoAplicaA =0
			set @SeAnunciaSTR = 'Pasaje válido para viajar hasta ' + convert(varchar(30), @pFechaTope, 3)
			-- set @SeAnunciaSTR = 'Vto. ' + convert(varchar(30), @pFechaTope, 3)+' Sujeto a Modificacion Tarifaria al Confirmar'

			IF exists(select 1 from Pasajes_Reimpresiones with(nolock)where Pasajes_Reimpresiones.Pasaje = @Pasaje)
			BEGIN
				set @Comentario = 'Comprobante de Vta Distribuida' 
				set @Comentario2='No Valido con:'
				set @Comentario3='Fines Tributarios'
				SELECT @BoleteriaAutorizada = Nombre FROM Boleterias WITH(NOLOCK) WHERE ID in (SELECT BoleteriaAutorizada FROM Pasajes_Reimpresiones WITH(NOLOCK) WHERE Pasaje = @Pasaje)
			END
			
		else
			set @SeAnunciaSTR = 'VTO. ' + convert(varchar(30), @pFechaTope, 3)
	END
	SET @vTipoLineaNombre =''
end


--CONNECTORS
select @ConnectorNombre = '', @ConnectorBoleto = ''
if exists(select 1 from Connectors_Pasajes with(nolock) where PasajeID = @Pasaje) and (select Type	from Connectors with(nolock) 	where ConnectorID = (select top 1 ConnectorID from Connectors_Pasajes with(nolock) where PasajeID = @Pasaje)) = 1
begin
	select @ConnectorNombre = Nombre
	from Connectors with(nolock)
	where ConnectorID = (select top 1 ConnectorID from Connectors_Pasajes with(nolock) where PasajeID = @Pasaje)

	select @ConnectorBoleto = ISNULL(IdentificacionConnector.value('data(/identificacion/@Boleto)[1]','varchar(20)'),'')
	from Connectors_Pasajes with(nolock) 
	where PasajeID = @Pasaje
end

declare @VIP varchar(3)
select @VIP=''
if @pPersona IS NOT NULL AND @pPersona != -1
begin
	select @personaDocumentoTipoINT=DocumentoTipo ,@personaDocumento=Documento, @personaNombre=Nombres, @PersonaTelefono = Telefonos, @personaApellido=Apellido, @personaFechaNacimiento=FechaNacimiento,@PersonaProfesion=Profesion,@Pais=g_direcciones.PaisID, @NacionalidadID=nacionalidad,@PersonaSexo=Sexo,
		@personaDomicilio = g_direcciones.calle+' '+isnull(cast(g_direcciones.numero as varchar),''),
		@personaTipoCNRT = case 
							when (dbo.CNRTCalculateAge(personas.FechaNacimiento, getdate())) <18 then '0'
							else '1' 
							end 
	from personas WITH(NOLOCK)
	left outer join g_DireccionesOwners WITH(NOLOCK)ON g_DireccionesOwners.OwnerID = @pPersona AND g_DireccionesOwners.direccionTipo=2
	left outer join g_direcciones WITH(NOLOCK)ON g_Direcciones.DireccionID = g_DireccionesOwners.DireccionID
	where id=@pPersona

	if exists(select 1 from pf_solicitudes with(nolock) where personaId = @pPersona) select @VIP = 'VIP'
	
	if @personaDocumento is null
		set @personaDocumento=''

	SELECT @personaDocumentoTipo = ISNULL(Codigo,'') FROM G_PaisesDocumentos WITH (NOLOCK) WHERE PaisDocumentoID=@personaDocumentoTipoINT
	
	SET @personaFechaNacimientoSTR = ''
	IF @personaFechaNacimiento IS NOT NULL 
		set @personaFechaNacimientoSTR=convert(varchar(30), @personaFechaNacimiento, 3)

	SELECT @Nacionalidad=Nombre from G_Paises WITH(NOLOCK)WHERE PaisId=@NacionalidadID
	IF @Nacionalidad IS NULL OR @Nacionalidad = ''
		set @Nacionalidad = 'ARGENTINA'					
	SET @PersonaProfesionSTR=''
	IF @PersonaProfesion IS NOT NULL
		SELECT @PersonaProfesionSTR=Nombre from CRM_profesiones WITH(NOLOCK)WHERE @PersonaProfesion=CRM_profesiones.ProfesionID
	
	if exists(select 1 from pf_puntos with(nolock) where personaId=@pPersona and estado=0)
		select @PF_SaldoPuntos = SUM(KmSaldo)
		from pf_puntos with(nolock) where personaId=@pPersona and estado=0
	
	IF @PersonaSexo=0 set @PersonaSexoSTR='MASCULINO'
	IF @PersonaSexo=1 set @PersonaSexoSTR='FEMENINO'
	IF @PersonaSexo IS NULL set @PersonaSexoSTR=' '
end
else
begin
	set @PersonaProfesionSTR=' '
	set @Nacionalidad = 'ARGENTINA'
	set @personaFechaNacimientoSTR = '**/**/**'
	set @PersonaSexoSTR=' '
end

--PARCHE BLUT!!!!
IF DB_NAME() = 'WF_BLUT'
BEGIN
	DECLARE @JujuyNumeroOrden smallint
	DECLARE @OrigenOrden smallint
	DECLARE @DestinoOrden smallint
	SELECT @OrigenOrden=Numero_Orden FROM ViajesRecorridos WITH (NOLOCK)WHERE Viaje= @pViaje AND Terminal = @pTerminalOrigen
	SELECT @DestinoOrden=Numero_Orden FROM ViajesRecorridos WITH (NOLOCK) WHERE Viaje= @pViaje AND Terminal = @pTerminalDestino

	IF @vLinea in (11, 15, 16, 17) or @Servicio IN (175, 222, 223, 225, 226, 244, 256, 257, 260, 261, 262, 270, 274, 316, 345, 346, 457, 197, 198, 239, 264, 405, 406, 454, 224, 253, 258, 263, 272, 275, 342, 350, 393, 394, 312, 313, 314, 315, 317, 320, 323)
		BEGIN
			SELECT @JujuyNumeroOrden=Numero_Orden FROM ViajesRecorridos WITH (NOLOCK) WHERE Viaje= @pViaje AND Terminal = 66
			
			IF @OrigenOrden < @JujuyNumeroOrden AND @DestinoOrden > @JujuyNumeroOrden
				BEGIN
					SELECT @LocalidadDestinoSTR = 'JUJUY CONTINUACION '+@LocalidadDestinoSTR
					SELECT @LocalidadDestinoETSTR = 'JUY CON '+@LocalidadDestinoETSTR
					SELECT @SeAnunciaSTR = 'JUJUY CONTINUACION '+@SeAnunciaSTR
				END
		END
	IF @Servicio in (36,37,38,39,219) AND 
	(SELECT RegionId FROM G_Localidades WITH(NOLOCK) WHERE LocalidadId IN (SELECT Localidad FROM Terminales WITH(NOLOCK)WHERE Id = @pTerminalOrigen)) = 10 -- IDA Linea 8
	BEGIN
		SELECT @LocalidadOrigenSTR = L.Nombre FROM G_Localidades L WITH(NOLOCK) WHERE LocalidadID = 9643
		SELECT @TerminalOrigenSTR = T.Nombre FROM Terminales T WITH(NOLOCK) WHERE ID = 122
		SELECT @LocalidadOrigenETSTR = LE.Nombre FROM LocalidadesEmpresasTransportadoras LE WITH(NOLOCK) WHERE Localidad = 9643 and empresa=@pEmpresa
	END
	IF @Servicio in (40,41,42,43,193) AND 
	(SELECT RegionId FROM G_Localidades WITH(NOLOCK) WHERE LocalidadId IN (SELECT Localidad FROM Terminales WITH(NOLOCK)WHERE Id = @pTerminalDestino)) = 10 -- Vuelta Linea 8
	BEGIN
		SELECT @LocalidadDestinoSTR = L.Nombre FROM G_Localidades L WITH(NOLOCK) WHERE LocalidadID = 9643
		SELECT @TerminalDestinoSTR = T.Nombre FROM Terminales T WITH(NOLOCK) WHERE ID = 122
		SELECT @LocalidadDestinoETSTR = LE.Nombre FROM LocalidadesEmpresasTransportadoras LE WITH(NOLOCK) WHERE Localidad = 9643 and empresa=@pEmpresa
	END
	IF @Servicio in (189,220) --IDA Linea 18
	BEGIN
		SELECT @LocalidadDestinoSTR = L.Nombre FROM G_Localidades L WITH(NOLOCK) WHERE LocalidadId = 27886
		SELECT @TerminalDestinoSTR = T.Nombre FROM Terminales T WITH(NOLOCK) WHERE ID = 170
		SELECT @LocalidadDestinoETSTR = LE.Nombre FROM LocalidadesEmpresasTransportadoras LE WITH(NOLOCK) WHERE Localidad = 27886 and empresa=@pEmpresa
	END
	IF @Servicio in (190,221) --VUELTA Linea 18
	BEGIN
		SELECT @LocalidadOrigenSTR = L.Nombre FROM G_Localidades L WITH(NOLOCK) WHERE LocalidadId = 27886
		SELECT @TerminalOrigenSTR = T.Nombre FROM Terminales T WITH(NOLOCK) WHERE ID = 170
		SELECT @LocalidadOrigenETSTR = LE.Nombre FROM LocalidadesEmpresasTransportadoras LE WITH(NOLOCK) WHERE Localidad = 27886 and empresa=@pEmpresa
	END
END
--PARCHE NSDA!!!!
declare @ImpuestosDetallados varchar(400)
select @ImpuestosDetallados=''
IF DB_NAME() in ('WF_NSDA','WF_NSDA_TEST')
BEGIN
	IF @pViaje is null
		select @SeAnunciaSTR = ''
	IF @Servicio =126
	BEGIN
		SELECT @OrigenOrden =Numero_Orden FROM ViajesRecorridos WITH (NOLOCK)WHERE Viaje= @pViaje AND Terminal = @pTerminalOrigen
		SELECT @DestinoOrden =Numero_Orden FROM ViajesRecorridos WITH (NOLOCK)WHERE Viaje= @pViaje AND Terminal = @pTerminalDestino
	
		IF @OrigenOrden >1 AND @OrigenOrden <9
		BEGIN
			SELECT @LocalidadOrigenSTR =Nombre FROM dbo.G_Localidades WITH(NOLOCK)WHERE LocalidadId =1
			SELECT @LocalidadOrigenETSTR =Nombre FROM dbo.LocalidadesEmpresasTransportadoras WITH(NOLOCK)WHERE localidad =1 and empresa =@pEmpresa
		END
		IF @DestinoOrden >12 AND @DestinoOrden <21
		BEGIN
			SELECT @LocalidadDestinoSTR =Nombre FROM dbo.G_Localidades WITH(NOLOCK)WHERE LocalidadId =21
			SELECT @LocalidadDestinoETSTR =Nombre FROM dbo.LocalidadesEmpresasTransportadoras WITH(NOLOCK)WHERE localidad =21 and empresa =@pEmpresa
		END
	END
	IF @Servicio =145
	BEGIN
		SELECT @OrigenOrden =Numero_Orden FROM ViajesRecorridos WITH(NOLOCK)WHERE Viaje= @pViaje AND Terminal = @pTerminalOrigen
		SELECT @DestinoOrden =Numero_Orden FROM ViajesRecorridos WITH(NOLOCK)WHERE Viaje= @pViaje AND Terminal = @pTerminalDestino
	
		IF @OrigenOrden >=1 AND @OrigenOrden <9
		BEGIN
			SELECT @LocalidadOrigenSTR =Nombre FROM dbo.G_Localidades WITH(NOLOCK)WHERE LocalidadId =1
			SELECT @LocalidadOrigenETSTR =Nombre FROM dbo.LocalidadesEmpresasTransportadoras WITH(NOLOCK)WHERE localidad =1 and empresa =@pEmpresa
			SELECT @LocalidadDestinoSTR =Nombre FROM dbo.G_Localidades WITH(NOLOCK)WHERE LocalidadId =12
			SELECT @LocalidadDestinoETSTR =Nombre FROM dbo.LocalidadesEmpresasTransportadoras WITH(NOLOCK)WHERE localidad =12 and empresa =@pEmpresa
		END
	END

	declare @alicuotaIVAID int
	select @alicuotaIVAID = dbo.IVA_GetAlicuotaIDPaisByConfiguracion(@BoleteriaId, @CS_IVARestriccion, @CS_IVARestriccionSobre, @pLocalidadOrigen, @pLocalidadDestino, dbo.GETLOCALDATE(null))
	
	declare @Gravado10 money, @Gravado5 money, @IVA10 money, @IVA5 money
	if (select alicuota from TAX_ImpuestosAlicuotas with(nolock) where ImpuestoAlicuotaID=@alicuotaIVAID)=10
	begin
		select @Gravado10 = @poImporteOperacion * baseImponible / 100
		from TAX_ImpuestosAlicuotas with(nolock) 
		where ImpuestoAlicuotaID=@alicuotaIVAID

		select @IVA10 = @Gravado10 * alicuota / 100
		from TAX_ImpuestosAlicuotas with(nolock) 
		where ImpuestoAlicuotaID=@alicuotaIVAID
	end
	if (select alicuota from TAX_ImpuestosAlicuotas with(nolock) where ImpuestoAlicuotaID=@alicuotaIVAID)=5
	begin
		select @Gravado5 = @poImporteOperacion * baseImponible / 100
		from TAX_ImpuestosAlicuotas with(nolock) 
		where ImpuestoAlicuotaID=@alicuotaIVAID

		select @IVA5 = @Gravado10 * alicuota / 100
		from TAX_ImpuestosAlicuotas with(nolock) 
		where ImpuestoAlicuotaID=@alicuotaIVAID
	end

	declare @Timbrado varchar(20), @Vencimiento varchar(15)
	select @Timbrado=numero, @Vencimiento=CONVERT(varchar,FechaValidezHasta,108)
	from TAX_ImpuestosTimbrados with(nolock)
	where ImpuestoID = (select ImpuestoID from TAX_ImpuestosAlicuotas with(nolock) where ImpuestoAlicuotaID=@alicuotaIVAID)
	and dbo.getlocaldate(null) between FechaValidezDesde and FechaValidezHasta
	and S_PrestadorID=(select S_PrestadorID from TAX_AdministradoresTributarios with(nolock) where AdministradorTributarioID=(select AdministradorTributarioID from TAX_Impuestos with(nolock) where ImpuestoID=(select ImpuestoID from TAX_ImpuestosAlicuotas with(nolock) where ImpuestoAlicuotaID=@alicuotaIVAID)))

	select @ImpuestosDetallados = 'Timbrado="'+ISNULL(@Timbrado,'')+'" TimbradoVencimiento="'+ISNULL(@Vencimiento,'')+'" Gravado10="'+cast(ISNULL(@Gravado10,0) as varchar)+'" Gravado5="'+cast(ISNULL(@Gravado5,0) as varchar)+'" GravadoExentas="0" IVA10="'+cast(ISNULL(@IVA10,0) as varchar)+'" IVA5="'+cast(ISNULL(@IVA5,0) as varchar)+'" '
END
------------
-- EMPRESA CUENTACORRENTISTA
SELECT @CtaCte_EmpresaID=EmpresaClienteID FROM EmpresasClientesPasajesOperaciones WITH(NOLOCK) WHERE PasajeID=@Pasaje AND Operacion IN(0,13)
SELECT @CtaCte_Empresa=Nombre, @CtaCte_Empresa_CUIT=CUIT FROM EmpresasClientes WITH(NOLOCK) WHERE EmpresaID=@CtaCte_EmpresaID
IF @CtaCte_Empresa IS NULL
	SET @CtaCte_Empresa=''
----------------------------


EXEC Viaje_GetEtiquetaSTR @vTipo, @pViaje, @ServicioSTR OUTPUT

set @Coche=(select nombre from coches WITH(NOLOCK)where coches.id =(select coche from viajes WITH(NOLOCK)where viajes.id= @pViaje))
if @Coche is null set @Coche=' '

DECLARE @Plataforma varchar(50)
SELECT @Plataforma = Plataforma FROM TerminalesServiciosPlataformas WITH(NOLOCK) WHERE TerminalID = @pTerminalOrigen AND ServicioID = @Servicio
IF @Plataforma IS NULL
	SELECT @Plataforma = Plataformas FROM TerminalesEmpresasTransportadoras WITH(NOLOCK) WHERE Terminal = @pTerminalOrigen and Empresa=@pEmpresa
IF @Plataforma IS NULL
	SELECT @Plataforma = ''


IF @Operacion = @OPERACION_REIMPRESION_COMPROBANTE
	BEGIN
	select @Comentario = '', @Comentario2 = ''
		set @Comentario='Comprobante de Reimpresion de Boleto, no valido para Viajar'
		set @Comentario2='No valido para Viajar'
--		set @Comentario='Transferencia, sin derecho a Devolucion ni cambio de Fecha'


		IF db_name() in ('WF_OLTR', 'WF_OLTR2')
			BEGIN
				set @Comentario='Venta Distribuida'
				set @Comentario2='No valido para viajar'
				set @Comentario3='No valido para:'
				set @Comentario4 ='Efectos Tributarios'
				set @tipoVenta= ' '	
			END
		ELSE
			BEGIN
				select @tipoVenta= 'Crédito'	
			END
	end

IF @Operacion = @OPERACION_CAMBIOFECHA
BEGIN
 set @Comentario = 'Comprobante de Cambio de Fecha'-- de Pasaje '+RTRIM(@pNumero)
	set @Comentario2=''
	set @tipoVenta='Cambio de Fecha'
 

END
IF @Operacion = @OPERACION_DEVOLUCION
BEGIN
	set @tipoVenta='Devolucion'
 set @Comentario = 'Comprobante de Devolucion' 
		if db_name() = 'WF_BLUT' set @Comentario = @Comentario + '. No valido para viajar'
	set @Comentario2='No valido para Viajar'
 
	SET @poImporteOperacion = @poImporteOperacion * -1
	select @poImporteOperacion=@poImporteOperacion-@pPercepciones
	SET @pImporteDescuentos = @pImporteTotal - @poImporteOperacion
	
	SET @pImporteTotal = @poImporteOperacion
	SET @poIVAImporte = 0
	
END



IF @Operacion = @OPERACION_ANULACION
BEGIN
	set @tipoVenta='Anulación'
	set @Comentario = 'Comprobante de Anulacion'
	if db_name() = 'WF_BLUT' set @Comentario = @Comentario + '. No valido para viajar'
	set @Comentario2='No valido para Viajar'
	 
END

IF @Operacion=@OPERACION_DEJARABIERTO
begin
	set @tipoVenta='Dejar Abierto'
	SET @poImporteOperacion = (select importeoperacion from pasajesoperaciones WITH(NOLOCK)where Id = dbo.Pasaje_GetPasajeOperacionOriginal(@Pasaje,5))
	set @Comentario = 'Boleto con fecha abierta.'
	set @Comentario2='No valido para Viajar'
	 

	if db_name() in ('WF_OLTR', 'WF_OLTR2')
		BEGIN
			set @tipoVenta=''
			set @Comentario = 'Fecha Abierta'
			set @Comentario2=''
			
		END
end

select @PasajeCanjeTarifaBase = '', @PasajeCanjeTarifaFinal = '', @DiferenciaTarifaria = ''

IF @Operacion != @OPERACION_VENTA
BEGIN
	IF EXISTS (SELECT 1 FROM Pasajes_Canjes WITH(NOLOCK) WHERE PasajeGeneradoID=@Pasaje)
	begin
			declare @PasajeCanjeID int

			select @PasajeCanjeID = PasajeCanjeadoID
			from Pasajes_Canjes WITH(NOLOCK)
			WHERE Pasajes_Canjes.PasajeGeneradoID=@Pasaje

			select @pCanjeNumero = Numero, 
			@PasajeCanjeTarifaBase= cast(ImporteBase as varchar(20)),
			@PasajeCanjeTarifaFinal = cast(ImporteFinal as varchar(20))
			from Pasajes with(nolock)
			where Id=@PasajeCanjeID

			select @DiferenciaTarifaria = cast(ImporteOperacion as varchar(20))
			from PasajesOperaciones with(nolock)
			where Operacion=6 and Pasaje=@PasajeCanjeID

	end
	ELSE 
	begin
			SELECT @pCanjeNumero = @pNumero
			select @DiferenciaTarifaria = cast(ImporteOperacion as varchar(20))
			from PasajesOperaciones with(nolock)
			where Operacion=6 and Pasaje=@Pasaje
	end
	set @PasajeCanje='Pasaje Numero '+RTRIM(@pCanjeNumero)
END



IF db_name() in ('WF_OLTR', 'WF_OLTR2')
BEGIN
	if @pMedioPagoTipo = @MEDIOPAGOTIPO_CTACTE 
		select @tipoVenta= 'Crédito'	
END


-----CASTEOS DE TARIFAS DE INT A VARCHAR
DECLARE @strTB varchar (20)
DECLARE @strTD varchar (20)
DECLARE @strTT varchar (20), @strSumTT_BT varchar(20)
DECLARE @strTT2 varchar (20)
DECLARE @strTB_BT varchar (20)
DECLARE @strTD_BT varchar (20)
DECLARE @strTT_BT varchar (20)



SELECT @strTB =cast(@pTarifaBase as varchar(20)), @strTD =cast(@pImporteDescuentos as varchar(20)), @strTT =cast(@pImporteTotal as varchar(20))
SELECT @strTB_BT =@strTB, @strTD_BT =@strTD, @strTT_BT =@strTT, @strSumTT_BT=@strTT

if DB_NAME() = 'WF_FLAM' select @strTT = '$ ' + dbo.FormatNumber(@pImporteTotal, 2, '.', ',', '-')

-- LE SACO LOS DECIMALES PARA COOMOTOR Y DEMO
IF DB_NAME() in ('WF_COOM', 'WF_COOM_LEARN', 'WF_COOM_TEST', 'WF_DEMO')
BEGIN
	SELECT @strTB =cast(cast(@pTarifaBase as int) as varchar(20)), @strTD =cast(cast(@pImporteDescuentos as int) as varchar(20)), @strTT =cast(cast(@pImporteTotal as int) as varchar(20))
	SELECT @strTB_BT =@strTB, @strTD_BT =@strTD, @strTT_BT =@strTT, @strSumTT_BT=@strTT
END 


IF EXISTS(SELECT 1 FROM Pasajes_Seguros WITH(NOLOCK) WHERE (PasajeMenorID = @Pasaje OR PasajeMayorID = @Pasaje) AND Estado = 1)
BEGIN
	
	DECLARE @AcompPasajeID int
	DECLARE @AcompMonedaID smallint
	
	IF EXISTS(SELECT 1 FROM Pasajes_Seguros WITH(NOLOCK) WHERE PasajeMayorID = @Pasaje AND Estado = 1)
		SELECT 	@AcompPasajeID = PasajeMenorID FROM Pasajes_Seguros WITH(NOLOCK) WHERE PasajeMayorID = @Pasaje AND Estado = 1
	ELSE
		SELECT 	@AcompPasajeID = PasajeMayorID FROM Pasajes_Seguros WITH(NOLOCK) WHERE PasajeMenorID = @Pasaje AND Estado = 1

	SELECT @AcompMonedaID = MonedaID FROM PasajesOperaciones WITH(NOLOCK) WHERE Pasaje = @AcompPasajeID AND Operacion IN (0, 13)
	
	SELECT @SeguroCotizacionIndice = 1.00
	IF @AcompMonedaID != @poMonedaID
	BEGIN
		--MONEDAS DIFERENTES, APLICO COTIZACION 
		
		EXEC CO_ConvertMoney @poMonedaID, @AcompMonedaID, @poFechaOperacion, 1, @SeguroCotizacionIndice OUTPUT
		
		IF EXISTS(SELECT 1 FROM Pasajes_Seguros WITH(NOLOCK) WHERE PasajeMayorID = @Pasaje AND Estado = 1)
			SELECT @SeguroCotizacionIndice = 1.00 / ISNULL(@SeguroCotizacionIndice,1.00)
		
	END
	
END

-- Si es un seguro limpio las tarifas


IF exists(SELECT top 1 1
FROM Configuraciones with(nolock)
where Type=9 AND Owner=0
and ConfigXML.value('data(/XML/seguro/pasajesTipos/pasajeTipo/@pasajeTipoId)[1]','int') = @pPasajeTipo
and ConfigXML.value('data(/XML/seguro/pasajesTipos/pasajeTipo/@paisId)[1]','int') = @paisBoleteria)
BEGIN
	SELECT @strTB =cast(@pImporteTotal as varchar(20))
	SELECT @strTD ='0'
-- LE SACO LOS DECIMALES PARA COOMOTOR Y DEMO
	IF DB_NAME() in ('WF_COOM', 'WF_COOM_LEARN', 'WF_COOM_TEST', 'WF_DEMO', 'FICS', 'WF_COPE', 'WF_COPE_TEST')
	BEGIN
		SELECT @strTT =cast(cast(@pImporteTotal as int) as varchar(20))
	END
	ELSE
	BEGIN
		SELECT @strTT =cast(@pImporteTotal as varchar(20))
	END
	if DB_NAME() in ('WF_PBUS','WF_TEST','WF_HELP')
		select @Comentario4 = 'SEGURO DE MENOR'
END




---- Parche Crucero
IF DB_NAME() = 'WF_CNOR'
BEGIN
	SET @strTT=cast(@StrSumTT_BT as varchar(20))
	SET @strTT2=cast(@StrSumTT_BT as varchar(20))

	IF (@Servicio=322 or @Servicio=609)
		BEGIN
			set @Comentario4='No Incluye Servicios a Bordo'
		END

 IF @Servicio in(653,654,655,656)
		BEGIN
			set @Comentario4='Horario sujeto a trafico Aduanero y Migratorio'
		END


	IF @pPasajeTipo in (10,176,177,178,342,373,542,543,544)
	BEGIN
		SELECT @ComentarioNegrita = 'BUTACA TURISTICA. BOLETO SIN CAMBIO NI DEVOLUCION'
		SELECT @strTB_BT ='BT', @strTD_BT ='BT', @strSumTT_BT ='BT', @strTT_BT='BT'
		SELECT @strTT = '0'
		SELECT @strTT2= '0'
	END
	--IF @pPasajeTipo in (49, 50, 51, 52, 53, 54)

	IF @pPasajeTipo in (49, 50, 51, 52, 53, 54, 341, 342, 343, 346, 374)
	BEGIN
		SELECT @strTB_BT = ''
		SELECT @strTT = '0'
		SELECT @strTT2= '0'
	END

		
	IF @pPasajeTipo in (302, 303, 304, 4,365,522,523,524,525,526,527,528,529,530,531,532,533,284,287,297,309,310,311,462,463,464,394,395,396,397,483,484,485,537,538,539,389,392,540,349,344,348,314,317,318,319,320,321,322,352,547,584,574,575,576,577,578,579,59,60,61,62,63,64,65,66,68,69,70,71,72,73,74,75,76,77,78,79,80,81)
	BEGIN
		 --Setea en la variable el importe de la tarifa base, se imprime en el talon del pasajero tarifa base en el talon de agencia tarifa final
		SET @strTT2 =cast(@pTarifaBase as varchar(20))
	END
	
	
--	IF @pPasajeTipo =523
--		BEGIN
--			
--			set @strTB_BT= @strSumTT_BT 
--			set @Comentario4='NO VALIDO PARA VIAJAR'
--	END

	IF @Servicio IN (693,694)
	BEGIN
		DECLARE @FALCONNumeroOrden smallint
		DECLARE @OrigenOrden1 smallint
		DECLARE @DestinoOrden1 smallint
	
		SELECT @OrigenOrden1=Numero_Orden FROM ViajesRecorridos WHERE Viaje= @pViaje AND Terminal = @pTerminalOrigen
		SELECT @DestinoOrden1=Numero_Orden FROM ViajesRecorridos WHERE Viaje= @pViaje AND Terminal = @pTerminalDestino

		SELECT @FALCONNumeroOrden=Numero_Orden FROM ViajesRecorridos WHERE Viaje= @pViaje AND Terminal = 416
			
		IF (@DestinoOrden1 < @FALCONNumeroOrden and @Servicio=694)
			BEGIN
				set @LocalidadDestinoSTR = 'Puerto Falcon'
				set @TerminalDestinoSTR = 'Cruce Pto Falcon'
			END
			
			
		IF (@OrigenOrden1 > @FALCONNumeroOrden and @Servicio=693)
			BEGIN
				set @LocalidadOrigenSTR = 'Puerto Falcon'
				set @TerminalOrigenSTR = 'Cruce Pto Falcon'
			END
	END
	
	
END

declare @comentario5 varchar(80)
select @comentario5 =''
 --Cables de Conexiones
 if @ConexionOrden > 0
 begin
	--@ConexionOrden tiene el orden en la combinacion, 1 si es el primer pasaje y 2 si es el segundo, 
	--los ID de pasajes se guardan en Venta_Conexiones_Pasajes
	declare @OtroPasajeID int
select @OtroPasajeID = max(PasajeID) from Venta_Conexiones_Pasajes with(nolock) 
			where Orden!=@ConexionOrden and VentaConexionID in (select VentaConexionID from Venta_Conexiones_Pasajes with(nolock) where PasajeID=@Pasaje)
	if DB_NAME() in('WF_CNOR1','WF_CNOR') and @ConexionOrden=2 and (select ImpresionServicio from TFC_ServiciosConexiones with(nolock) where ServicioConexionID=@ConexionID)=0
	begin
			select @comentario5 = ''+(select Nombre from Terminales with(nolock) where Id= (select TerminalOrigen from Pasajes with(nolock) where Pasajes.Id=@OtroPasajeID)) + ' '+convert(varchar,(select FechaPartida from ViajesRecorridos with(nolock) where Viaje=(select Viaje from Pasajes with(nolock) where Pasajes.Id=@OtroPasajeID) and Terminal=(select TerminalOrigen from Pasajes with(nolock) where Pasajes.Id=@OtroPasajeID)), 108)
	end
	if DB_NAME() in('WF_CNOR1','WF_CNOR') and @ConexionOrden=1 and (select ImpresionConexion from TFC_ServiciosConexiones with(nolock) where ServicioConexionID=@ConexionID)=0
	begin
			select @comentario5 = ''+(select Nombre from Terminales with(nolock) where Id= (select Terminalorigen from Pasajes with(nolock) where Pasajes.Id=@OtroPasajeID)) + ' '+convert(varchar,(select FechaPartida from ViajesRecorridos with(nolock) where Viaje=(select Viaje from Pasajes with(nolock) where Pasajes.Id=@OtroPasajeID) and Terminal=(select TerminalOrigen from Pasajes with(nolock) where Pasajes.Id=@OtroPasajeID)), 108)+' - ' +(select Nombre from Terminales with(nolock) where Id= (select Terminaldestino from Pasajes with(nolock) where Pasajes.Id=@OtroPasajeID))
	end
 	
 end


---Parche Singer
IF DB_NAME() = 'WF_SING'
BEGIN
	IF @pPasajeTipo in (42,43,167,222,223,224,225,226,227,228,229,231,232,233,234,235,236,237,238,239,167)
	BEGIN
		SET @pImporteTotal=@pTarifaBase
		SET @pImporteTotal=@pTarifaBase
		SET @strTT=@pTarifaBase
		SET @pImporteDescuentos=0
		SET @strtd=0
	END
END

---Parche Ersa
IF DB_NAME() in ('WF_ERSA','WF_ERSA_TEST')
BEGIN
	IF @pPasajeTipo in (128,129,130,131)
	BEGIN
		SET @pImporteTotal=@pTarifaBase
		SET @pImporteTotal=@pTarifaBase
		SET @strTT=@pTarifaBase
		SET @pImporteDescuentos=0
		SET @strtd=0
	END
END

if db_name() in ('FICS.ERSA')
	BEGIN
		
		IF @pPasajeTipo in (511)
		BEGIN
			IF @vCategoria=9
			BEGIN
				SET @strTT= '9000.00'
				SET @strTB = '9000.00'
				SET @strTD= '0.00'
			END
		END
		END

		BEGIN
		
		IF @pPasajeTipo in (512,537)
		BEGIN
			IF @vCategoria=8
			BEGIN
				SET @strTT= '9320.00'
				SET @strTB = '9320.00'
				SET @strTD= '0.00'
			END
		END
		END

	BEGIN
	IF @pPasajeTipo in (536)
		BEGIN
			IF @vCategoria=9
			BEGIN
				SET @strTT= '9000.00'
				SET @strTB = '9000.00'
				SET @strTD= '0.00'
			END
		END
		END

	BEGIN
	IF @pPasajeTipo in (517)
		BEGIN
			IF @vCategoria=9
			BEGIN
				SET @strTT= '11040.00'
				SET @strTB = '11040.00'
				SET @strTD= '0.00'
			END
		END
		END

	BEGIN
	IF @pPasajeTipo in (27)
			BEGIN
				SET @strTT= '17680.00'
				SET @strTB = '17680.00'
				SET @strTD= '0.00'
			END
	END

	BEGIN
	IF @pPasajeTipo in (541)
			BEGIN
				SET @strTT= '20160.00'
				SET @strTB = '20160.00'
				SET @strTD= '0.00'
			END
	END

    BEGIN
	IF @pPasajeTipo in (555)
			BEGIN
				SET @strTT= '23320.00'
				SET @strTB = '23320.00'
				SET @strTD= '0.00'
			END
	END





----CABLE CATA IMPRIME VALOR BT EN LOS IMPORTES
--- En Servicios TUR01 y TUR02 y para cualquiera de la boleteria 027MZ
IF DB_NAME() = 'WF_CATA'
BEGIN
	IF (@Servicio=18 or @Servicio=19) OR (@poBoleteria =42) OR @pPasajeTipo =69
	BEGIN
			set @strTB='BT'
			set @strTD='BT'
			set @strTT='BT'
	END
	IF (@Servicio = 561)
	begin
		set @Comentario = @Comentario + 'Sale del Hotel OPERA -Falucho 1938 Primero Noveno -Tercero Octavo'
	end
END


set @pHoraPresentacion=' '
if db_name() = 'WF_TCNI'
begin
	set @pHoraPresentacion=' '
	if @pLocalidadOrigen=18148 and @pLocalidadDestino=23174
		set @pHoraPresentacion='Hora Presentacion: 07:30'

	if @pLocalidadOrigen=18148 and @pLocalidadDestino<>23174
		set @pHoraPresentacion='Hora Presentacion: 07:30'

	if @pLocalidadOrigen=18155 
		set @pHoraPresentacion='Hora Presentacion: 04:30'

	if @pLocalidadOrigen=15251 and @pLocalidadDestino=18148
		set @pHoraPresentacion='Hora Presentacion: 08:00'

	if @pLocalidadOrigen=15251 and @pLocalidadDestino=18154
		set @pHoraPresentacion='Hora Presentacion: 08:00'

	if @pLocalidadOrigen=15251 and @pLocalidadDestino=18155
		set @pHoraPresentacion='Hora Presentacion: 08:00'

	if @pLocalidadOrigen=4274 
		set @pHoraPresentacion='Hora Presentacion: 20:00'
end


if db_name() = 'WF_BLUT'
begin
	IF @pPasajeTipo in (84, 81, 89, 98)
	begin
		select @strTT = @strTB
		select @strTD = '0'
	end
end

declare @COPE_CATEGORIABANIO tinyint, @Matricula varchar(10), @Interno varchar(30)
select @COPE_CATEGORIABANIO = 2
declare @CatBanio varchar(1), @CatOtros varchar(1)
select @CatBanio = '', @CatOtros = ''
if db_name() = 'WF_COPE'
begin
	if @vCategoria = @COPE_CATEGORIABANIO select @CatBanio = 'X'
	else select @CatOtros = 'X'
	select @vCoche = dbo.Viaje_GetCocheByViajeTerminal(@pViaje, @pTerminalOrigen, @vTerminalDestino)
	select @Matricula=matricula, @Interno=Nombre from coches with(nolock) where id = @vCoche
end

declare @ImporteTotalSTR varchar(200)
select @ImporteTotalSTR=dbo.fn_Num2Let(isnull(@pImporteTotal,0))

SET @pBarCode =replace(replace(replace(replace(replace(@pBarCode, '&', '&amp;'), '"', '&quot;'), CHAR(39), '&apos;'), '>', '&gt;'), '<', '&lt;')

declare @strFechaHoraOperacion varchar(30), @strHoraOperacion varchar(30), @strFechaOperacion varchar(30), @strFechaOperacionVenta varchar(30)

select @strFechaHoraOperacion = convert(varchar(30), @poFechaOperacion, 3) + ' ' + convert(varchar(30), @poFechaOperacion, 8)
select @strFechaOperacion = convert(varchar(30), @poFechaOperacion, 3), @strFechaOperacionVenta = convert(varchar(30), @poVentaFechaOperacion, 3)
select @strHoraOperacion = convert(varchar(30), @poFechaOperacion, 8)
if @strFechaOperacionVenta is null select @strFechaOperacionVenta = @strFechaOperacion

if db_name() in ('WF_OLTR', 'WF_OLTR2')
begin
	select @Moneda=Simbolo, @MonedaLiteral=Nombre from monedas with(nolock) where id = (SELECT MonedaID FROM PasajesTipos WITH(NOLOCK) WHERE Id=@pPasajeTipo)	
	select @NumeroComprobanteDevolucion=ComprobanteNumero from Pasajes_Comprobantes with(nolock) where pasajeId = @Pasaje and Operacion=2
	select @ImporteTotalSTR = @ImporteTotalSTR + ' ' + @MonedaLiteral
	set @MonedaLiteral = ''
	
end



IF db_name() in ('WF_OLTR', 'WF_OLTR2')
BEGIN
	if @pMedioPagoTipo = @MEDIOPAGOTIPO_CTACTE 
		select @tipoVenta= 'Crédito'
 if @pImporteDescuentos > 0 
 begin
 select @strTD = '0' , @strTB = @strTT
 end	
END


IF DB_NAME() = 'WF_PTIR'
BEGIN
	if @pMedioPagoTipo = @MEDIOPAGOTIPO_CTACTE 
	begin
	select @Comentario = ISNULL(@Comentario,'') + 'A facturar en cta cte'	
	select @strTT = ''
	select @pasajeTipoPorcentage = ''
	select @strTB = ''
	select @strTD = ''
	select @pasajeTipoPorcentage = ''
	end
END

--PARCHE NSDA
IF DB_NAME() = 'WF_NSDA'
BEGIN

-- Setea como origen del pasaje la cabecera del servicio
if @servicio in (150, 181,187,191,192,193,194,195, 199)
BEGIN

/*
declare @pLocalidadOrigen LOCALIDAD_ID
declare @pTerminalOrigen TERMINAL_ID
declare @pLocalidadDestino LOCALIDAD_ID
declare @pTerminalDestino TERMINAL_ID
*/

set @pLocalidadOrigen = (select LocalidadOrigen from servicios where id=@servicio)
set @pTerminalOrigen = (select TerminalOrigen from servicios where id=@servicio)
set @pLocalidadDestino = (select LocalidadDestino from servicios where id=@servicio)
set @pTerminalDestino = (select TerminalDestino from servicios where id=@servicio)
END


	if @BoleteriaId in (109 , 55 , 84 , 64 , 149 , 61 , 148 , 138 , 65 , 66 , 89 , 74 , 75 , 129)
	set @Comentario = 'ORIENTACION AL CONSUMIDOR PROVINCIA DE BUENOS AIRES 0800 222 9042 Ley 13987'
	else
	begin
		set @Comentario = ''
	end
END

--PARCHE PRNA

IF DB_NAME() = 'WF_PRNA'
BEGIN
	if @pPasajeTipo = 11
	set @Comentario = 'Descuento 25%'
	else
	begin
		set @Comentario = ''
	end
	
	if @pPasajeTipo in (16, 2, 9, 7, 8)
	set @Comentario = 'Descuento 50%'
	else
	begin
		set @Comentario = ''
	end
	
	if @pPasajeTipo = 10
	set @Comentario = 'Descuento 75%'
	else
	begin
		set @Comentario = ''
	end
END

--PARCHE TATA

IF DB_NAME() = 'WF_TATA'
BEGIN
	IF @pViaje IS NULL
		BEGIN
			set @SeAnunciaSTR = 'Pasaje válido para viajar hasta ' + convert(varchar(30), @pFechaTope, 3)
		 IF @pLocalidadOrigen=16055	
			BEGIN
				set @Plataforma = 'PLATAFORMAS 23 A 26'	
			END
		 IF @pLocalidadOrigen=16121	
			BEGIN
				set @Plataforma = 'PLATAFORMAS 7 A 9'	
			END
			
		 IF @pLocalidadOrigen<>16121 AND @pLocalidadOrigen<>16055
			BEGIN
				set @Plataforma = ''	
			END
			
		END
	ELSE
		begin
			set @SeAnunciaSTR = @Plataforma
		end
END


IF DB_NAME() = ('WF_SLVA')
BEGIN
	IF @Servicio IN (SELECT id FROM dbo.Servicios WHERE Linea=18)
	BEGIN
		SET @pButaca ='--'
	END
END


IF DB_NAME() in ('WF_COPE', 'WF_COPE2')
BEGIN
	SELECT @personaApellidoNombre = @personaNombre + ' '+ @personaApellido 

	/*CABLE COMENTARIO SI EL SERVICIO TIENE CONEXION */
	IF EXISTS (select * from TFC_ServiciosConexiones where servicioid = @Servicio)
 		BEGIN
			set @Conexion = 'CONEXION' --COMENTARIO CONEXION
		END
END
ELSE
BEGIN
	SELECT @personaApellidoNombre = @personaApellido + ' '+ @personaNombre 
END


IF DB_NAME() = 'FICS.CTUR'
BEGIN
	IF @Servicio in (136) 
	BEGIN
		SET @SIdayVuelta = 'Servicio ida y vuelta/round trip ticket'
		SET @Departure = 'Salida/Departure 15:00HS'
	END
	ELSE IF @servicio in (147,154)
	BEGIN
		SET @SIdayVuelta = 'Servicio ida y vuelta/round trip ticket'
		SET @Departure = 'Salida/Departure'
	END
	ELSE
	BEGIN
		SET @HoraArribo = ''
		SET @SIdayVuelta = ''
		SET @Departure = ''
	END

	SELECT @pButaca = 'Butaca Libre - Free seat'
END

select @pViajeEtiqueta = Etiqueta from Viajes_Etiquetas with(nolock)where Viaje = @pViaje
if @pViajeEtiqueta is null
	select @pViajeEtiqueta = Etiqueta from Servicios with(nolock) where Id=@Servicio

Set @FechaPartidaAnio = cast(DATENAME ( Year, @pFechaPartida )as varchar(4))
Set @FechaPartidaMes = cast(Month(@pFechaPartida)as varchar(2))
If Len(@FechaPartidaMes) = 1 Set @FechaPartidaMes = '0' + @FechaPartidaMes
Set @FechaPartidaDia = cast(DATENAME ( Day, @pFechaPartida)as varchar(2))
Set @FechaArriboAnio = cast(DATENAME ( Year, @pFechaArribo) as varchar(4))
Set @FechaArriboMes = cast(Month(@pFechaArribo) as varchar(2))
If Len(@FechaArriboMes) = 1 Set @FechaArriboMes = '0' + @FechaArriboMes
Set @FechaArriboDia = cast(DATENAME ( Day, @pFechaArribo) as varchar(2))
Set @FechaOperacionAnio = cast(DATENAME ( Year, @poFechaOperacion) as varchar(4))
Set @FechaOperacionMes = case when Month(@poFechaOperacion) < 10 then '0' else '' end + cast(Month(@poFechaOperacion) as varchar(2))
If Len(@FechaArriboMes) = 1 Set @FechaArriboMes = '0' + @FechaArriboMes
Set @FechaOperacionDia = case when Day(@poFechaOperacion) < 10 then '0' else '' end + cast(Day(@poFechaOperacion) as varchar(2))

SELECT @TalonarioSerie=Serie, @TalonarioInicial = Inicial, @TalonarioFinal = Final, @CodigoAutorizacion = CodigoAutorizacion, @TalonarioVencimiento= format(FechaVencimiento, 'dd/MM/yyyy') FROM PasajesTalonarios WITH(NOLOCK) WHERE Id IN (SELECT Talonario FROM Pasajes WITH(NOLOCK) WHERE ID = @Pasaje)
SET @RangoTalonario = @TalonarioSerie + '-' + cast(@TalonarioInicial as varchar)+ ' al '+@TalonarioSerie + '-' + cast(@TalonarioFinal as varchar)

IF DB_NAME() in ('WF_OLTR', 'WF_OLTR2')
BEGIN
	IF EXISTS(SELECT 1 FROM PasajesOperaciones WITH(NOLOCK) WHERE Pasaje IN (SELECT PasajeCanjeadoID FROM Pasajes_Canjes PC WITH(NOLOCK) WHERE PC.PasajeGeneradoID = @Pasaje) AND Operacion = 16)
	BEGIN
		IF (SELECT ImporteFinal FROM Pasajes WITH(NOLOCK) WHERE Id = @Pasaje) < (SELECT ImporteFinal FROM Pasajes WITH(NOLOCK) WHERE Id = (SELECT PasajeCanjeadoID FROM Pasajes_Canjes PC WITH(NOLOCK) WHERE PC.PasajeGeneradoID = @Pasaje))
			SELECT @strTT = cast(ImporteFinal as varchar(20)), @strTB = cast(ImporteBase as varchar(20)), @strTD = cast(ImporteDescuentos as varchar(20)) FROM Pasajes WITH(NOLOCK) WHERE Id = (SELECT PasajeCanjeadoID FROM Pasajes_Canjes PC WITH(NOLOCK) WHERE PC.PasajeGeneradoID = @Pasaje)
	END
END
if isnumeric(@strTT)=1
SELECT @ImporteTotalSTR=dbo.fn_Num2Let(isnull(replace(replace(replace(@strTT,'.',''),'$',''),',','.'),0))
else
SELECT @ImporteTotalSTR=@strTT

select @ViajeDespachoID = ISNULL(ViajeDespachoID,0) from TFC_ViajesDespachos with(nolock) where ViajeID=@pViaje and TerminalID=@pTerminalOrigen

SELECT @PF_Puntos = CAST(SUM(KmSaldo) as varchar(20)) FROM PF_Puntos WITH(NOLOCK) WHERE PersonaId = @pPersona
SELECT @BoleteriaAutorizada = Nombre FROM Boleterias WITH(NOLOCK) WHERE ID in (SELECT BoleteriaAutorizada FROM Pasajes_Reimpresiones WITH(NOLOCK) WHERE Pasaje = @Pasaje)
IF @BoleteriaAutorizada IS NOT NULL
BEGIN
	SET @BoleteriaAutorizadaSTR = 'Retira en:'
END
IF @PF_Puntos IS NOT NULL
BEGIN
	SET @PF_PuntosSTR = 'Saldo de Puntos PF:'
END


if (DB_NAME() = 'WF_ETAP')
BEGIN 

	if @pEmpresa=14
	BEGIN
		SET @EMP_InicioActividad = '04-01-1991'
		SET @EMP_IngresosBrutos = 'CM907-332300-4'
	END
			
	if @pEmpresa=18
	BEGIN
		SET @EMP_InicioActividad = '01-11-1973'
		SET @EMP_IngresosBrutos = 'EXENTO'
	END

	if @pEmpresa=15
	BEGIN
		SET @EMP_InicioActividad = '07-09-2006'
		SET @EMP_IngresosBrutos = 'MCR85623-EX'
	END
		
END
SET @BOL_InicioActividad = REPLACE(CONVERT(varchar, (SELECT FechaIngreso FROM Boleterias WHERE @BoleteriaId = Id),105),'/','-')

declare @ImporteTotalSIVA varchar(20)
select @ImporteTotalSIVA = ''
if isnumeric(@strTT)=1
select @ImporteTotalSIVA = CAST(isnull(@strTT, 0) - ISNULL(@poIVAImporte,0) as varchar) 

declare @EsDiscapacitado int
select @EsDiscapacitado = 0
if(@pPasajeTipo=(select ConfigXml.value('data(/XML/ventas/@pasajeTipoDiscapacitados)[1]','int') from Configuraciones with(nolock) where Type=9 and Owner=0))
	select @EsDiscapacitado = 1

select @ETT_NOMBRE= nombre 
from esquemastarifarios ET with(nolock) 
where ET.Id = (select EsquemaTarifario from EsquemasTarifariosTarifas with(nolock) where Id=@ETT)


 --Cables de Conexiones
 if @ConexionOrden > 0
 begin
	--@ConexionOrden tiene el orden en la combinacion, 1 si es el primer pasaje y 2 si es el segundo, los ID de pasajes se guardan en Venta_Conexiones_Pasajes
	select @ConexionOrden = @ConexionOrden
 end

if db_name() = 'WF_FLAM' and @pMedioPagoTipo = @MEDIOPAGOTIPO_CTACTE select @strTT = @comprobante


IF DB_NAME() in ('WF_ERSA', 'WF_ERSA_TEST')
BEGIN
	IF @Servicio=18
	BEGIN
		IF @pTerminalOrigen=8 and @pTerminalDestino in (19,20,21,118,39,40,41,42,56,27,11,43,7,4,57,2,1,28,29,30,31,32,33,34,35,59)
		BEGIN 
			SET @pHoraPartida=cast((select datepart(dd, horapartida) from viajesrecorridos where viajesrecorridos.Viaje=@pViaje and viajesrecorridos.Terminal=8 and ViajesRecorridos.Numero_Orden>1) as tinyint)
		END
	END
END

---Parche EL PRACTICO
IF DB_NAME() in ('WF_PRAC', 'WF_PRAC_TEST')
BEGIN
	IF @pTerminalOrigen in (1,3,14,15,16,17,18,19,20,21,22) and @pTerminalDestino IN (23,24,25,52)
	BEGIN
		SET @TerminalDestinoSTR = 'Frontera (Santa Fe)'
	
	END
	IF @pTerminalOrigen in (23,24,25,52) and @pTerminalDestino IN (1,3,14,15,16,17,18,19,20,21,22)
	BEGIN
		SET @TerminalOrigenSTR = 'Frontera (Santa Fe)'
	END

	IF @pTerminalOrigen in (26) and @pTerminalDestino IN (41)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (26) and @pTerminalDestino IN (60)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (26) and @pTerminalDestino IN (61)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END

	
	IF @pTerminalOrigen in (26) and @pTerminalDestino IN (40)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (26) and @pTerminalDestino IN (28)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END
-----
	IF @pTerminalOrigen in (41) and @pTerminalDestino IN (26)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite provincial'
	
	END

	IF @pTerminalOrigen in (60) and @pTerminalDestino IN (26)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (61) and @pTerminalDestino IN (26)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
	
	END

	
	IF @pTerminalOrigen in (40) and @pTerminalDestino IN (26)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (28) and @pTerminalDestino IN (26)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
	
	END
	-----

	IF @pTerminalOrigen in (41) and @pTerminalDestino IN (60)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (41) and @pTerminalDestino IN (61)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial a Humbolt'
	
	END

	IF @pTerminalOrigen in (41) and @pTerminalDestino IN (40)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (41) and @pTerminalDestino IN (28)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END
	---
		IF @pTerminalOrigen in (60) and @pTerminalDestino IN (41)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (61) and @pTerminalDestino IN (41)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (40) and @pTerminalDestino IN (41)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (28) and @pTerminalDestino IN (41)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
 
	END
	----
	IF @pTerminalOrigen in (60) and @pTerminalDestino IN (61)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (60) and @pTerminalDestino IN (40)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (60) and @pTerminalDestino IN (28)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END
	-----
		IF @pTerminalOrigen in (61) and @pTerminalDestino IN (60)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (40) and @pTerminalDestino IN (60)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (28) and @pTerminalDestino IN (60)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
	
	END
	----
	IF @pTerminalOrigen in (61) and @pTerminalDestino IN (40)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (61) and @pTerminalDestino IN (28)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END
	----
	IF @pTerminalOrigen in (40) and @pTerminalDestino IN (61)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (28) and @pTerminalDestino IN (61)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
	
	END
	---
	IF @pTerminalOrigen in (40) and @pTerminalDestino IN (28)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	----
	END
	
	IF @pTerminalOrigen in (28) and @pTerminalDestino IN (40)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
	
	END
	-----
		IF @pTerminalOrigen in (23) and @pTerminalDestino IN (25)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (25) and @pTerminalDestino IN (23)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END

			IF @pTerminalOrigen in (23) and @pTerminalDestino IN (3)
	BEGIN
		SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (3) and @pTerminalDestino IN (23)
	BEGIN
		SET @TerminalDestinoSTR = 'Limite Provincial'
	
	--	PARCHE ÑANANDU DEL SUR
	END	

	IF @pTerminalOrigen in (64,67,68,76,77,79,80) and @pTerminalDestino IN (81)
	BEGIN
	SET @TerminalDestinoSTR = 'Limite Provincial'
	
	END

	IF @pTerminalOrigen in (81) and @pTerminalDestino IN (64,67,68,76,77,79,80)
	BEGIN
	SET @TerminalOrigenSTR = 'Limite Provincial'
	
	END

	
	IF @pPasajeTipo in (3)
	BEGIN
		SET @pImporteTotal= 0
		SET @strTB = 0
		SET @strTD = 0
		SET @comentario5 = 'Sin valor comercial'	
	END
	IF @pPasajeTipo in (4)
	BEGIN
		SET @pImporteTotal= 0
		SET @strTB = 0
		SET @strTD = 0
		SET @comentario5 = 'Aplica RG513/2013'
			END
	IF @pPasajeTipo in (20)
	BEGIN
		SET @pImporteTotal= 0
		SET @strTB = 0
		SET @strTD = 0
		SET @comentario5 = 'Aplica Ley 26928'
	END
	IF @pPasajeTipo in (36,37)
 BEGIN
 SET @pImporteTotal= ' '
 SET @strTT = ' '
 SET @strTB = ' '
 SET @strTD = ' ' 
 END
END
----parche trafico libre vs. servicio publico
if db_name() in ('WF_PRAC')
	BEGIN
		if @Servicio in (1,2,3,4,5,6,7,8,11,12,13,14,15,16,28,29,30,31,32,33)
			BEGIN
				SET @Comentario3='TRAFICO LIBRE'
				END
		if @Servicio in (9,10,17,18,19,20,21,23,24,25,26,35,38)
				SET @Comentario4='SERVICIO PUBLICO'
				END



IF DB_NAME() in ('WF_ERSA', 'WF_ERSA_TEST')
BEGIN
	IF @pFechaPartida > '2015-03-16' and @pEmpresa in (2,1) and @pTerminalOrigen = 1
	BEGIN
		SET @Plataforma = '37-55'
	END
END
IF DB_NAME() in ('WF_SING')
BEGIN
	IF @pFechaPartida > '2015-03-16' and @pEmpresa in (1) and @pTerminalOrigen in (77,209)
	BEGIN
		SET @Plataforma = '37-55'
	END
END


if db_name() in ('WF_ERSA')
	BEGIN
		
		if @pEmpresa=1
			BEGIN
				SET @Comentario4='905-260869-1'
			END
			
			if @pEmpresa=2
			BEGIN
				SET @Comentario4='905-261169-8'
			END
			if @pEmpresa=3
			BEGIN
				SET @Comentario4='905-054960-1'
			END
				
		IF @pPasajeTipo in (22)
		BEGIN
			SET @strTT=@strTB
			SET @strTD= '0.00'
			 
		END

		IF @pPasajeTipo IN (7)
		BEGIN
			SET @pasajeTipoNombre = 'Descuento 20%'
		END

		IF @pPasajeTipo in (5)
		BEGIN
			IF @vCategoria=1
			BEGIN
				SET @strTT= '769.00'
				SET @strTB = '769.00'
				SET @strTD= '0.00'
			END
			IF @vCategoria=5
			BEGIN
				SET @strTT= '1014.00'
				SET @strTB = '1014.00'
				SET @strTD= '0.00'
			END
		END
			SET @Comentario5= (select texto from Comentarios where tipo=21 and owner=@Pasaje)
	END
	
	if db_name() in ('WF_BUSS')
	BEGIN
		
		if @pEmpresa=1
			BEGIN
				SET @Comentario='PRUEBA1'
				SET @Comentario2='PRUEBA2'
				SET @Comentario3='PRUEBA3'
				SET @Comentario4='PRUEBA4'
				SET @Comentario5=''
			END
		IF @Operacion = @OPERACION_ANULACION
			BEGIN
				SET @ComprAnulacion = 'Comprobante de ANULACION'
			END
		IF (@paisBoleteria = 152) AND ((@pTerminalOrigen = 8 AND @pTerminalDestino = 1) OR (@pTerminalOrigen = 7 AND @pTerminalDestino = 2) OR (@pTerminalOrigen = 6 AND @pTerminalDestino = 1))
		BEGIN

			DECLARE @tPesosI money, @tPesosIV money

			--SACO EL IMPORTE EN PESOS DEL ESQUEMA GENERAL
			SELECT TOP 1 @tPesosI = Precio_OneWay, @tPesosIV = Precio_RoundTrip
			FROM EsquemasTarifariosTarifas ETT WITH(NOLOCK)
			INNER JOIN EsquemasTarifarios ET WITH(NOLOCK) ON ET.Id = ETT.EsquemaTarifario
			INNER JOIN Monedas ON Monedas.Id = ET.MonedaID
			WHERE TerminalOrigen = @pTerminalOrigen AND TerminalDestino = @pTerminalDestino AND ETT.Fecha_Fin > GETDATE() AND Monedas.Pais = 32 AND ETT.Estado = 0 AND ET.Id = 2

			SET @strTD = ''
			SELECT @Moneda=Simbolo, @MonedaLiteral=Nombre from monedas with(nolock) where id = 1 --PESOS ARGENTINOS
			IF (@pIdaVuelta=0) 
			BEGIN
				SET @strTB = @tPesosI
				SET @strTT = @tPesosI
			END
			ELSE IF (@pIdaVuelta = 1) 
			BEGIN 
				SET @strTB = @tPesosIV
				SET @strTT = @tPesosIV
			END
		END
	END


--SE REEMPLAZAN LOS CARACTERES QUE ROMPEN EL XML. LA SOLUCION DEFINITIVA SERIA MANDAR <CDATA< valor >> PERO HABIA QUE CAMBIAR LA DLL PARA QUE LEA 
--LOS VALORES INTERNOS DEL XML. SE HABLO CON MATIAS PEZZARINI Y AUTORIZO EL CAMIBIO DE CARACTERES POR * Y COMILLAS Y APOSTROFE POR ´
select @CtaCte_Empresa = REPLACE(@CtaCte_Empresa, '>', '*')
select @CtaCte_Empresa = REPLACE(@CtaCte_Empresa, '<', '*')
select @CtaCte_Empresa = REPLACE(@CtaCte_Empresa, '&', '*')
select @CtaCte_Empresa = REPLACE(@CtaCte_Empresa, '"', '´')
select @CtaCte_Empresa = REPLACE(@CtaCte_Empresa, '''', '´')

--VARIABLES NUEVAS PARA LOS COMPROBANTES DE DEVOLUCIONES
SET @ImporteTotaDevolucion = (SELECT ImporteOperacion FROM PasajesOperaciones WHERE Pasaje = @Pasaje and Operacion = 2)
SET @ImporteRetencion = (SELECT ImporteOperacion FROM PasajesOperaciones WHERE Pasaje = @Pasaje and Operacion = 0) + (SELECT ImporteOperacion FROM PasajesOperaciones WHERE Pasaje = @Pasaje and Operacion = 2)
SET @PorcentajeRetencion = ((@ImporteRetencion*100)/(SELECT ImporteOperacion FROM PasajesOperaciones WHERE Pasaje = @Pasaje and Operacion = 0))

--VARIABLES NUEVAS PARA TELEFONO y DIRECCION DE TERMINALES
SET @TerminalDireccionOrigen = (SELECT 'Calle: ' + Calle +' ,CP: '+CodPostal FROM Terminales WHERE Id = @pTerminalOrigen)
SET @TerminalTelefonoOrigen = (SELECT Telefonos FROM Terminales WHERE Id = @pTerminalOrigen)
SET @TerminalDireccionDestino = (SELECT 'Calle: ' + Calle +' ,CP: '+CodPostal FROM Terminales WHERE Id = @pTerminalDestino)
SET @TerminalTelefonoDestino = (SELECT Telefonos FROM Terminales WHERE Id = @pTerminalDestino)


--VARIABLE PARA EL IMPORTE BASE EN DOLARES TASAS DE EMBARQUE Y FORMTEO DEL PASAJE
IF DB_NAME() in ('WF_SOLP', 'WF_SOLP1')
	BEGIN
		set @Comentario4= (select valor from TerminalesTasasEmbarque where TerminalID=@pTerminalOrigen)
		
		IF (@poMonedaID = 1)
			BEGIN
				SET @ImporteBaseDolares = @pTarifaBase / (SELECT Valor FROM CO_MonedasCotizaciones 
				WHERE MonedaReferencia = 1 and MonedaCotizada = 5 and SYSDATETIME() between VigenteDesde and VigenteHasta)
			END
		ELSE IF (@poMonedaID = 2)
			BEGIN
				SET @ImporteBaseDolares = @pTarifaBase / (SELECT Valor FROM CO_MonedasCotizaciones 
				WHERE MonedaReferencia = 2 and MonedaCotizada = 5 and SYSDATETIME() between VigenteDesde and VigenteHasta)
			END
		ELSE IF (@poMonedaID = 3)
			BEGIN
				SET @ImporteBaseDolares = @pTarifaBase / (SELECT Valor FROM CO_MonedasCotizaciones 
				WHERE MonedaReferencia = 3 and MonedaCotizada = 5 and SYSDATETIME() between VigenteDesde and VigenteHasta)
			END
		ELSE IF (@poMonedaID = 4)
			BEGIN
				SET @ImporteBaseDolares = @pTarifaBase / (SELECT Valor FROM CO_MonedasCotizaciones 
				WHERE MonedaReferencia = 4 and MonedaCotizada = 5 and SYSDATETIME() between VigenteDesde and VigenteHasta)
			END
		ELSE IF (@poMonedaID = 5)
			BEGIN
				SET @ImporteBaseDolares = @pTarifaBase
			END
		
		declare @Serie varchar (3)
		declare @Numero varchar (7)

		set @Serie=substring (@pNumero,1,3)
		set @Numero=substring (@pNumero,5,10)
		declare @width int = 7 -- desired width
		declare @pad char(1) = '0' -- pad character
		set @Numero = replicate(@pad ,@width-len(convert(varchar(100),@Numero)))+ convert(varchar(10),@Numero)
		
		set @pNumero= @Serie + '-' + @Numero

	END

IF DB_NAME() in ('WF_PALM', 'WF_TEST')
BEGIN
	IF @pPasajeTipo IN (4,5,6,7,8,9,10,11,12,13,14,15,16,17,19,22,23,24,25,26) 
		BEGIN
		 SET @pasajeTipoNombre ='Tarifa Completa'
	END
END 

---PARCHE GOMEZ HERNANDEZ
IF DB_NAME() in ('FICS.GOHR')
BEGIN
	IF @pTerminalOrigen in (17,18,19,20) and @pTerminalDestino IN (58,52,50,59,51,23,60,61,62,63,64,65,66,78,79,80,81,82,83,84,85,86,87,77)
	BEGIN
		SET @OmegConex += @TerminalOrigenSTR
		SET @TerminalOrigenSTR = 'TER. TURBO'
	END

	IF @pTerminalOrigen in (58,52,50,59,51,23,60,61,62,63,64,65,66,78,79,80,81,82,83,84,85,86,87,77) and @pTerminalDestino IN (17,18,19,20)
	BEGIN
		SET @OmegConex += @TerminalDestinoSTR
		SET @TerminalDestinoSTR = 'TER. TURBO'
	END

	IF @pTerminalOrigen in (17,18,19) and @pTerminalDestino IN (57,36)
	BEGIN
		SET @OmegConex += @TerminalOrigenSTR
		SET @TerminalOrigenSTR = 'TER. CHIGORODO'
	END

	IF @pTerminalOrigen in (57,36) and @pTerminalDestino IN (17,18,19)
	BEGIN
		SET @OmegConex += @TerminalDestinoSTR
		SET @TerminalDestinoSTR = 'TER. CHIGORODO'
	END
END

--PARCHE OMEGA CONEXION
IF DB_NAME() = 'FICS.OMEG'
BEGIN
IF @servicio in (167,168,169,170,176)
	BEGIN
		IF @pTerminalOrigen in (1) and @pTerminalDestino in (16,17)
			BEGIN
				SET @OmegConex += @TerminalDestinoSTR
				SET @TerminalDestinoSTR = 'Term. BUCARAMANGA'
			END
		END
IF @servicio in (171,172,173,175,177,178,179)
	BEGIN
		IF @pTerminalOrigen in (16,17,45,46,44,85) and @pTerminalDestino in (1)
			BEGIN
				SET @OmegConex += @TerminalDestinoSTR
				SET @TerminalDestinoSTR = 'Term. BUCARAMANGA'
			END
		END
IF @servicio in (174)
	BEGIN
		IF @pTerminalOrigen in (1) and @pTerminalDestino in (16,17)
			BEGIN
				SET @OmegConex += @TerminalDestinoSTR
				SET @TerminalDestinoSTR = 'PUERTO BOYACA'
		 END
	 END
IF @servicio in (183,184,185,186)
	BEGIN
		IF @pTerminalOrigen in (1,63,66,77) and @pTerminalDestino in (32,31,48,47,51,52,53,78,3,61)
			BEGIN
				SET @OmegConex += @TerminalDestinoSTR
				SET @TerminalDestinoSTR = 'LA DORADA'
		END
	END
	IF @servicio in (188)
	BEGIN
		IF @pTerminalOrigen in (1,2) and @pTerminalDestino in (31,33,34,47,49)
			BEGIN
				SET @OmegConex += @TerminalDestinoSTR
				SET @TerminalDestinoSTR = 'CIMITARRA'
		END
	END
		IF @servicio in (189)
	BEGIN
		IF @pTerminalOrigen in (31,33,34,47,49) and @pTerminalDestino in (1,4)
			BEGIN
				SET @OmegConex += @TerminalDestinoSTR
				SET @TerminalDestinoSTR = 'CIMITARRA'
		END
	END
END 


declare @localidadOrigenCP varchar(10)	
select @localidadOrigenCP = isnull(isnull(nullif((select CodPostal from Terminales with(nolock) where Id=@pTerminalOrigen),''),(select CodPostal from G_Localidades with(nolock) where LocalidadId=@pLocalidadOrigen)),'')	
declare @localidadDestinoCP varchar(10)	
select @localidadDestinoCP = isnull(isnull(nullif((select CodPostal from Terminales with(nolock) where Id=@pTerminalDestino),''),(select CodPostal from G_Localidades with(nolock) where LocalidadId=@pLocalidadDestino)),'')
	


--Variable nueva para código dinámico de terminal
declare @SistemaExternoID int
declare @pasajeRecorridoId int
declare @pasajeEmpresaId int

set @CodigoConfigSTR = ''
select @CodigoConfigXML = CodigoConfig from Terminales with(nolock) where Terminales.Id = @pTerminalOrigen
if @CodigoConfigXML is not null
BEGIN


 --Crear tablaConNombre/Valor	
 DECLARE @ValoresXML table(Valor varchar(40), Campo varchar(40))	
 insert into @ValoresXML (Campo, Valor) values 	
 ( 'Butaca', isnull(rtrim(@pButaca), '')),	
 ('PasajeNumero', isnull(rtrim(@pNumero), '')),	
 ('FechaPartida', isnull(@FechaPartidaSTR, '')),	
 ('FechaPartidaAnio', isnull(@FechaPartidaAnio, '')),	
 ('FechaPartidaMes', isnull(@FechaPartidaMes, '')),	
 ('FechaPartidaDia', isnull(@FechaPartidaDia, '')),	
 ('FechaPartidaCompleta', isnull(@FechaPartidaFullYearSTR, '')),	
 ('LocalidadOrigen', rtrim(isnull(@LocalidadOrigenSTR,''))),	
 ('LocalidadDestino', rtrim(isnull(@LocalidadDestinoSTR,''))),	
 ('LocalidadOrigenCP', isnull(@localidadOrigenCP,'')),	
 ('LocalidadDestinoCP', isnull(@localidadDestinoCP,'')),	
 ('CocheMatricula', isnull(@cocheMatricula, '')),	
 ('HoraPartida', isnull(@HoraPartidaSTR, '')) ,	
 ('Viaje', cast(isnull(@pViaje, '') as varchar(10)))
	--select @pasajeRecorridoId

	select @pasajeEmpresaId = Empresa from pasajes with(nolock) where pasajes.Id = @Pasaje
	select @pasajeRecorridoId = Recorrido from Servicios with(nolock) where Servicios.Id = @Servicio

	select @SistemaExternoID = Nodo.value('data(./@id)[1]','int') 
	FROM @CodigoConfigXML.nodes('XML/sistExterno') AS NewTable(Nodo)	

	DECLARE @ResultsXML table(Valor varchar(20), Longitud int, Tipo int)
	insert into @ResultsXML
	select 
	 CASE Nodo.value('data(./@tipo)[1]','int') 
		WHEN 0 THEN CAST(Nodo.value('data(./@valor)[1]','varchar(20)') AS varchar(20))
		WHEN 1 THEN isnull((select top 1 Codigo from SistemasExternosEntidadesCodigos with(nolock) where (SistemaExternoID = @SistemaExternoID and TargetType = Nodo.value('data(./@valor)[1]','varchar(10)') and TargetID = @pasajeEmpresaId and Nodo.value('data(./@valor)[1]','varchar(10)') = 24) or (SistemaExternoID = @SistemaExternoID and TargetType = Nodo.value('data(./@valor)[1]','varchar(10)') and TargetID = @pasajeRecorridoId and Nodo.value('data(./@valor)[1]','varchar(10)') = 25)),'')
		--WHEN 2 THEN CAST(Nodo.value('data(./@valor)[1]','varchar(20)') AS varchar(20))
		WHEN 2 THEN (select top 1 Valor from @ValoresXML where Campo = Nodo.value('data(./@valor)[1]','varchar(20)'))
		END,
		Nodo.value('data(./@largo)[1]','int'),
		Nodo.value('data(./@tipo)[1]','int')
	FROM @CodigoConfigXML.nodes('XML/campos/campo') AS NewTable(Nodo)	
	

	/*
	DECLARE @cValor varchar(20)
	DECLARE cResults CURSOR READ_ONLY FAST_FORWARD FOR
		SELECT Valor 
		FROM @ResultsXML
		where Tipo = 2

		OPEN cResults
		FETCH NEXT FROM cResults INTO @cValor 
		
		WHILE (@@fetch_status <> -1)
		BEGIN

			Create Table #x(val varchar(20))
			insert into #x
			exec Pasaje_GetColumnsDinamically @cValor,@Pasaje 

			update @ResultsXML set Valor = (select top 1 val from #x)
			where Valor = @cValor
			
			DROP TABLE #x
			FETCH NEXT FROM cResults INTO @cValor
		END
		CLOSE cResults
		DEALLOCATE cResults
		*/


	--Proceso los resultados
	DECLARE @ResultsFilter table(Value varchar(20))
	insert into @ResultsFilter select
	case 
	when Longitud <= len(Valor) then substring(Valor, 1, Longitud)
	ELSE REPLICATE('0',Longitud-LEN(Valor)) + Valor
	end
	from @ResultsXML

	select @CodigoConfigSTR = COALESCE(@CodigoConfigSTR + '', '') + Value
	from @ResultsFilter

	--select @CodigoConfigSTR = REPLACE(@CodigoConfigSTR, '-', '')
	--select @CodigoConfigSTR = REPLACE(@CodigoConfigSTR, 'COM', ',')
END

/*TKT 7530*/
IF DB_NAME() in ('WF_CNOR')
BEGIN
	IF @pMedioPagoTipo in (2,7)
	BEGIN
		SET @TarjSinDev = 'SIN DEVOLUCION'
	END
END

/*TKT 7565*/
if db_name() in ('WF_CNOR','WF_CNOR_TEST' )
	BEGIN
		
		if @pEmpresa=1
			BEGIN
				SET @Comentario='914-30626296250'
				SET @Comentario1 = 'CUIT:'
				SET @Comentario8 = 'Resp. Insc.'
				SET @Comentario3='18-11-1987'
				SET @Comentario4='Ruta 12 km. 8 1/2 - Garupá- Misiones - Argentina'				
			END
			
			if @pEmpresa=23
			BEGIN
			 SET @Comentario='901-30544089664'
				SET @Comentario1 = 'CUIT:'
				SET @Comentario8 = 'Resp. Insc.'
				SET @Comentario3='02-10-1973'
				SET @Comentario4=' Carlos Pellegrini N° 1149 Piso 1 Dpto. 3 - C.A.B.A - Argentina'	
			END
			if @pEmpresa=15
			BEGIN
				SET @Comentario='901-30544089664'
				SET @Comentario1 = 'CUIT:'
				SET @Comentario8 = 'Resp. Insc.'
				SET @Comentario3='02-10-1973'
				SET @Comentario4=' Carlos Pellegrini N° 1149 Piso 1 Dpto. 3 - C.A.B.A - Argentina'	
			END
			if @pEmpresa=17
			BEGIN
				SET @Comentario=''
				SET @Comentario1 = 'RUC:'
				SET @Comentario8 = ''
				SET @Comentario3='29-10-1993'
				SET @Comentario4='Granada N° 612 - Asunción - Paraguay'	
			END
				if @pEmpresa=49
			BEGIN
				SET @Comentario=''
				SET @Comentario1 = 'RUC:'
				SET @Comentario8 = ''
				SET @Comentario3='21-11-1985'
				SET @Comentario4='Dr. Eligio Ayala N° 988 - Asunción - Paraguay'	
			END
	END

/*TKT 8639*/
DECLARE @pInteres money 
SET @pInteres = (SELECT TOP 1 Interes FROM PasajesTiposMediosPago WHERE MedioPagoID = @pMedioPago AND Cuota = @pMedioPagoCuotas AND PasajeTipoID = @pPasajeTipo)
SET @PorcInteres = ('%' + CAST (@pInteres AS VARCHAR))
DECLARE @descuentoTemp money

IF(@pImporteDescuentos < 0)
	SET @descuentoTemp = @pImporteDescuentos* -1
ELSE 
	SET @descuentoTemp = @pImporteDescuentos

SET @ImpInteres = ((@pTarifaBase - @descuentoTemp)* @pInteres) / 100

IF EXISTS (select top 1 1 from pap_pasajes where pasajeid = @Pasaje)
BEGIN
	select 
	@PAP_ORIGEN = PAPV.DireccionOrigen,
	@PAP_DESTINO = PAPV.DireccionDestino,
	@PAP_ORIGENENTRE = PAPV.DireccionOrigenEntre,
	@PAP_DESTINOENTRE = PAPV.DireccionDestinoEntre
	from pap_pasajes PAPA
	inner join pap_ventas PAPV on PAPV.papventaid = PAPA.papventaid
	where pasajeid = @Pasaje

	if(@TerminalOrigenIsPAP=1) SET @TerminalOrigenSTR = @PAP_ORIGEN
	if(@TerminalDestinoIsPAP=1) SET @TerminalDestinoSTR = @PAP_DESTINO
END

/** CABLE SINGER SIN CATERING ABORDO**/
if db_name() in ('WF_ERSA')
 BEGIN
 
 if @Servicio in (237,238,239,240,241,242,243,244,247,248)
 BEGIN
 SET @SinServicioAbordo='SIN SERVICIO A BORDO' 
 END
 END

if (DB_NAME() = 'FICS.TRIN')
BEGIN

 if @pEmpresa=1
 BEGIN
 SET @EMP_InicioActividad = '04-01-1991'
 SET @EMP_IngresosBrutos = '913-504578-3'
 END
 
 if @pEmpresa=2
 BEGIN
 SET @EMP_InicioActividad = '06-09-99'
 SET @EMP_IngresosBrutos = '032-076026-09'
 END

 if @pEmpresa=3
 BEGIN
 SET @EMP_InicioActividad = '01-01-2002'
 SET @EMP_IngresosBrutos = '8344705'
 END
 
END

IF (DB_NAME() = 'FICS.HUIL')
BEGIN
	IF @vCategoria in (2,3)
	BEGIN
		SET @Comentario4='**ESTE SERVICIO NO ES DIRECTO**'		
	END
END

DECLARE @strDescuentos varchar(20)
select @strDescuentos = cast(ImporteDescuentos as varchar(20)) from Pasajes with(nolock) where Pasajes.Id=@Pasaje


IF (DB_NAME() = 'FICS.GUEM')
BEGIN
	--SI EL TIPO DE BOLETO ES Boleto Educativo R34, EL IMPORTE SE MUESTRA EN 0
	if @pPasajeTipo in (34, 35, 36)
	begin
		SELECT @strTB = '0,00', @strTD = '0,00', @strTT = '0,00', @strDescuentos = '0,00', @pasajeTipoPorcentage = '0,00', @poIVAImporte = 0, @ImporteTotalSPercepcion = 0
	end
END

SET @PasajeComentario= (select top 1 texto from Comentarios where tipo=21 and owner=@Pasaje)

set @retval = '<pasajeXML MonedaID="'+isnull(cast(@poMonedaID as varchar),'')+'" MonedaPaisID="'+isnull(cast((select Pais from Monedas with(nolock) where Monedas.Id=@poMonedaID) as varchar),'')+'" Discapacitado="'+cast(@EsDiscapacitado as varchar)+'" PasajeTipoTipoDto="'+isnull(cast((select CategoriaDescuento from PasajesTipos with(nolock) where PasajesTipos.Id=@pPasajeTipo) as varchar),'1')+'" CateringID="'+isnull(cast((select Pasajes_ServiciosAbordo.ServicioAbordoID from Pasajes_ServiciosAbordo with(nolock) where PasajeID=@Pasaje) as varchar),'')+'" CategoriaID="'+cast(isnull(@vCategoria,0) as varchar)+'" ServicioID="'+cast(isnull(@Servicio,0) as varchar)+'" PasajeBarCode="' +@pBarCode + '" PasajeNumero="' + isnull(rtrim(@pNumero), '') + '" PasajeEstado="' + isnull(@PasajeEstadoSTR, '')
+ '" OperacionID="' + cast(@Operacion as varchar(2)) + '" CUIT="'+ ISNULL(@eEmpresaCUIT,'') +'" Transportadora="' + rtrim(ISNULL(@TransportadorSTR,'')) 
+ '" Boleteria="' + rtrim(isnull(@BoleteriaSTR,'')) + '" BoleteriaDireccion="'+isnull(@BoleteriaDireccionSTR, '')+'" BoleteriaCodigo="'+ISNULL(@BoleteriaCodigoSTR, '')+'" BoleteriaCUIT="'+isnull(@BoleteriaCUITSTR,'')+'" FechaHoraOperacion="' + isnull(@strFechaHoraOperacion,'') + '" LocalidadOrigen="' + rtrim(isnull(@LocalidadOrigenSTR,'')) 
+ '" LocalidadOrigenCP="'+ @localidadOrigenCP +'" LocalidadDestinoCP="'+ @localidadDestinoCP +'" LocalidadOrigenET="' + rtrim(ISNULL(@LocalidadOrigenETSTR,'')) + '" TerminalDestino="' + rtrim(isnull(@TerminalDestinoSTR,'')) +'" TerminalOrigen="' + rtrim(isnull(@TerminalOrigenSTR,'')) + '" TerminalDestinoID="' + rtrim(isnull(@pTerminalDestino,'')) +'" TerminalOrigenID="' + rtrim(isnull(@pTerminalOrigen,'')) 
+ '" LocalidadDestino="' + rtrim(isnull(@LocalidadDestinoSTR,'')) + '" LocalidadDestinoET="' + rtrim(ISNULL(@LocalidadDestinoETSTR,'')) 
+ '" SeAnuncia="' + isnull(@SeAnunciaSTR, '') + '" LocalidadAnuncia="'+isnull(@SeAnunciaLocalidadSTR, '')+'" FechaPartida="' + isnull(@FechaPartidaSTR, '') +'" FechaPartidaCompleta="' + isnull(@FechaPartidaFullYearSTR, '') 
+ '" EmpresaInicioAct.="' + isnull(@EMP_InicioActividad, '') + '" EmpresaIngBrutos="'+isnull(@EMP_IngresosBrutos, '')+'" BoleteriaInicioAct.="' + isnull(@BOL_InicioActividad, '') 
+'" FechaPartidaDia="' + isnull(@FechaPartidaDia, '') +'" FechaPartidaMes="' + isnull(@FechaPartidaMes, '') +'" FechaPartidaAnio="' + isnull(@FechaPartidaAnio, '') 
+ '" FechaArribo="' + isnull(@FechaArriboSTR, '') + '" ServicioNombre="' + isnull(@servicioNombre, '') + '" ServicioDescripcion="' + isnull(@servicioDescripcion, '') 
+ '" FechaArriboMes="' + isnull(@FechaArriboMes, '') + '" FechaArriboAnio="' + isnull(@FechaArriboAnio , '') + '" FechaArriboDia="' + isnull(@FechaArriboDia, '')
+ '" TerminalOrigenDireccion="' + isnull(@TerminalDireccionOrigen, '') + '" TerminalDestinoDireccion="' + isnull(@TerminalDireccionDestino , '') + '" TerminalOrigenTelefono="' + isnull(@TerminalTelefonoOrigen, '')+ '" TerminalDestinoTelefono="' + isnull(@TerminalTelefonoDestino, '')
+ '" HoraPartida="' + isnull(@HoraPartidaSTR,'')+ '" FechaHoraPartidaSTRAMPM="'+ISNULL(@FechaPartidaSTRAMPM,'')+'" HoraArribo="' + isnull(@HoraArribo,'')+ '" CategoriaServicio="' + isnull(@categoriaServicioNombre,'') + '" CategoriaTarifa="' + isnull(@categoriaTarifaNombre,'') 
+ '" FechaPartidaLiteral="' + @FechaPartidaLiteral + '" Butaca="' + @pButaca + '" NroOrdenFormacion="' + @nroOrdenFormacion + '" ServicioTipo="' + @ServicioSTR + '" Linea="' + @lineaNombre +'" TipoLinea="'+ @vTipoLineaNombre +'" TipoViaje="'+ isnull(cast(@vTipo as varchar),'') 
+ '" TarifaBase="' + isnull(@strTB,'') + '" Descuentos="'+isnull(@strDescuentos, '')+'" Descuento="' + isnull(@strTD,'') 
+ '" DescuentoPorcentaje="' + ISNULL (cast(@pasajeTipoPorcentage as varchar(10)), '') + '" IVAAlicuota="' + cast(ISNULL(@poIVAAlicuota,0) as varchar(10))
+ '" IVAImporte="' + cast(ISNULL(@poIVAImporte,0) as varchar(20)) + '" ImporteTotal="' + isnull(@strTT, '') + '" ImporteTotalSPecepcion="'+isnull(cast(@ImporteTotalSPercepcion as varchar),'')+'" Percepciones="'+isnull(@strPercepciones,'')+'" ImporteTotal2="' + isnull(@strTT2, '') + '" OpcionPago="' 
+ isnull(@pasajeTipoNombre,'') + '" MedioPago="' + isnull(@pMedioPagoNombre,'') + '" UsuarioCaja="'+CAST(isnull(@poCaja,'') as varchar(10))+'" UsuarioCodigo="' + rtrim(isnull(@UsuarioCodigoSTR, '')) + '" UsuarioNombre="' + rtrim(isnull(@UsuarioNombreSTR,'')) + '" UsuarioNombreCorto="' + rtrim(isnull(@UsuarioNombreCortoSTR,'')) + '" PersonaDocumento="' 
+ @personaDocumento + '" PersonaTipoCNRT="' + isnull(@personaTipoCNRT, '') + '" PersonaNombres="' + @personaNombre + '" PersonaApellido="' + @personaApellido + '" PersonaApellidoNombre="' + @personaApellidoNombre + '" PersonaApellidoNombreDocumento="' + @personaApellido + ' '+@personaNombre+ ' ' +@personaDocumento+ '" PersonaDocumentoTipo="' 
+ @personaDocumentoTipo + '" PersonaDocumentoTipoID="'+isnull(cast(@personaDocumentoTipoINT as varchar),'')+'" Domicilio="'+isnull(@personaDomicilio,'')+'" Nacimiento="'+@personaFechaNacimientoSTR + '" Ocupacion="'+ @PersonaProfesionSTR 
+ '" KGPermitidos="'+ ISNULL(@ServicioKGPermitidos,'') + '" EquipajePermitido="'+ ISNULL(@ServicioEquipajePermitido,'') + '" Comprobante="'+ ISNULL(@Comprobante, '')
+ '" Plataforma="'+ @Plataforma + '" FechaHoraPartida="'+ @FechaHoraPartidaSTR + '" Sexo="'
+ @PersonaSexoSTR + '" SexoV="'+ ISNULL(cast(@PersonaSexo as varchar),'0') + '" Nacionalidad="'+ @Nacionalidad + '" Voucher="'+@Voucher+'" PasajeComentario="'+isnull(@PasajeComentario, '') +'" comentarioInter="'+@ComentarioInter +'" Comentario="'+@Comentario+ '" Comentario3="'+ isnull(@Comentario3,'') + '" Comentario2="'+isnull(@Comentario2,'')+ '" Comentario4="'+isnull(@Comentario4,'')+ '" ComprAnulacion="'+isnull(@ComprAnulacion,'')+'" ConexionComentario="'+isnull(@Conexion, '')+
'" ComentarioNegrita="'+isnull(@ComentarioNegrita, '')+'" PasajeCanje="'+@PasajeCanje+'" CuentaCorrentista="'+isnull(@CtaCte_Empresa ,'')
+ '" ImporteExcesoEquipaje="' + isnull(CAST(@ImporteExcesoEquipaje as varchar), '')
+ '" ImporteBaseDolares="' + isnull(CAST(@ImporteBaseDolares as varchar), '')
+ '" ImporteSeguro="' + isnull(CAST(@SeguroImporte as varchar), '')
+ '" PasajeCosto="' + isnull(CAST(@PasajeCosto as varchar), '')
+ '" SIdayVuelta="'+isnull(@SIdayVuelta,'')
+ '" Departure="'+isnull(@Departure,'')
+ '" OmegConex="'+isnull(@OmegConex,'')
+ '" PAP_Origen="'+isnull(@PAP_ORIGEN,'')
+ '" PAP_Destino="'+isnull(@PAP_DESTINO,'')
+ '" PAP_OrigenEntre="'+isnull(@PAP_ORIGENENTRE,'')
+ '" PAP_DestinoEntre="'+isnull(@PAP_DESTINOENTRE,'')
+ '" Telefono_Empresa="'+isnull(@Telefono_Empresa,'')
+ '" SinServicioAbordo="'+isnull(@SinServicioAbordo,'')
+ '" PorcInteres="' + isnull(@PorcInteres, '')+ '" CantCuotas="' + case when @pMedioPagoCuotas IS NULL OR @pMedioPagoCuotas = 0 then '' else cast(@pMedioPagoCuotas as varchar) end+ '" ImpInteres="' + isnull(cast(@ImpInteres as varchar),'')
+ '" CuentaCorrentistaCUIT="'+ISNULL(@CtaCte_Empresa_CUIT,'')+'" Coche="'+@Coche + '" CategoriaBanio="'+@CatBanio+'" CategoriaOtro="'+@CatOtros+'" tipoVenta="'+@tipoVenta 
+ '" ImporteTotalBT="'+ISNULL(@strTT_BT, '')+'" TarifaBaseBT="'+isnull(@strTB_BT,'')+'" ImporteTotalSTR="'+isnull(@ImporteTotalSTR,'')+'" DescuentoBT="'+isnull(@strTD_BT,'')+'" ImporteRetencion="'+ISNULL(CAST(@ImporteRetencion as varchar(10)), '')+'" ImporteTotalDevolucion="'+ISNULL(CAST(@ImporteTotaDevolucion as varchar(10)), '')+'" PorcentajeRetencion="'+ISNULL(CAST(ROUND(@PorcentajeRetencion,2,2) as varchar(10))+'%', '')
+ '" Viaje="'+ cast(isnull(@pViaje, '') as varchar(10)) + case db_name() when 'WF_FLAM' then isnull(' (' + @ServicioCodigo + ')', '') else '' end + '" ViajeEtiqueta="'+isnull(@pViajeEtiqueta, '') +'" CocheNombre="'+isnull(@cocheNombre,'') +'" CocheMatricula="'+isnull(@cocheMatricula,'')+'" DireccionBoleteria="'+isnull(@DireccionBoleteria, '')
+ '" TelefonoBoleteria="'+isnull(@TelefonoBoleteria,'')+'" Multa="'+ISNULL(@Multa, '')+'" PV="'+isnull(@Matricula, '')+'" NI="'+isnull(@Interno, '')+'" VIP="'+isnull(@VIP, '')+'" FechaOperacionVenta="'+isnull(@strFechaOperacionVenta, '')+'" FechaOperacion="' + isnull(@strFechaOperacion,'') 
+ '" FechaOperacionAnio="' + isnull(@FechaOperacionAnio,'') + '" FechaOperacionDia="' + isnull(@FechaOperacionDia,'') + '" FechaOperacionMes="' + isnull(@FechaOperacionMes,'') 
+ '" HoraOperacion="'+isnull(@strHoraOperacion, '')+'" ImporteLiteral="'+isnull(@ImporteTotalSTR, '')+'" NumeroComprobanteDevolucion="'+isnull(@NumeroComprobanteDevolucion, 2)+'" Moneda="'+isnull(@Moneda, '')+'" MonedaLiteral="'+isnull(@MonedaLiteral, '')+'" MultaSTR="'+ISNULL(@MultaSTR, '')+ '" HoraPresentacion="'+ ISNULL(@pHoraPresentacion ,'')
+ '" PublicoX="'+ISNULL(@PublicoX, '')+'" EjecutivoX="'+ISNULL(@EjecutivoX, '')+'" ComunCaX="'+ISNULL(@ComunCaX, '')+'" ImporteNetoSumarizadoBT="' + isnull(@strSumTT_BT, '')+'" ImporteNetoSumarizado="' + isnull(@strTT, '') 
+ '" CotizacionImporteNetoSumarizado="'+ISNULL(CAST(@SeguroCotizacionIndice as varchar),'')+'" ConnectorNombre="'+@ConnectorNombre+'" ConnectorBoleto="'+@ConnectorBoleto+'" PF_PuntosCanjeados="'+ISNULL(CAST(@PF_PuntosCanjeados as varchar),'')+'" PF_SaldoPuntos="'+ISNULL(CAST(@PF_SaldoPuntos as varchar),'')
+ '" PersonaTelefono="'+ISNULL(@PersonaTelefono, '')+'" TalonarioVencimiento="'+ISNULL(CAST(@TalonarioVencimiento as varchar(10)), '')+'" RangoTalonario="'+ISNULL(CAST(@RangoTalonario as varchar(50)), '')+'" TalonarioInicial="'+ISNULL(CAST(@TalonarioInicial as varchar(20)), '')+'" TalonarioFinal="'+ISNULL(CAST(@TalonarioFinal as varchar(20)), '')+'" ImporteTotalSIVA="' + @ImporteTotalSIVA
+ '" ViajeDespachoID="'+CAST(isnull(@ViajeDespachoID,0) as varchar)+'" BoleteriaAutorizada="'+ISNULL(@BoleteriaAutorizada,'')+'" BoleteriaAutorizadaSTR="'+ISNULL(@BoleteriaAutorizadaSTR,'')
+ '" PF_Puntos="'+ISNULL(@PF_Puntos,'')+'" PF_PuntosSTR="'+ISNULL(@PF_PuntosSTR,'')+'" CodigoAutorizacion="'+ISNULL(@CodigoAutorizacion, '')+'" CodigoConfiguracionTerminal="'+ISNULL(@CodigoConfigSTR, '')
+ '" Comentario1="'+isnull(@Comentario1,'')+ '" Comentario5="'+isnull(@Comentario5,'')+ '" Comentario6="'+isnull(@Comentario6,'')+ '" Comentario7="'+isnull(@Comentario7,'')+ '" Comentario8="'+isnull(@Comentario8,'')
+ '" MicroSeguroLabel="' + isnull(@MicroSeguroLabel, '') +'" MicroSeguro="' + isnull(@strMicroSeguroImporte, '')
+ '" ImporteTotalSDecimal="' + isnull(cast(cast(@pImporteTotal as int) as varchar(20)), '')+'" ImporteTotalConExcesoEquipaje="' + isnull(cast(@TotalConExcesoEquipaje as varchar(20)), '')+'" ClaseTarifaria="'+@ClaseTarifaria+'" BasisCode="'+@RegulacionBasisCode+'" CanjeBase="'+@PasajeCanjeTarifaBase+'" CanjeFinal="'+@PasajeCanjeTarifaFinal+'" DifTarifa="'+@DiferenciaTarifaria+'" '+@ImpuestosDetallados+' TarifaBaseIda="'+isnull(cast(@ETT_TarifaIda as varchar),'')+'" TarifaBaseIdaVuelta="'+isnull(cast(@ETT_TarifaIdaVuelta as varchar),'')+'" TarifaBaseDiferencia="'+isnull(cast(@ETT_TarifaDiferencia as varchar),'')+'" EsquemaTarifarioNombre="'+ISNULL(@ETT_NOMBRE, '') + '" TarjSinDev="'+isnull(@TarjSinDev,'')+'"/>'
