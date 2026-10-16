*&---------------------------------------------------------------------*
*& Report ZQA_TRANSFER_REQUEST
*&---------------------------------------------------------------------*
*& Empresa   : QAMetrik Tecnologia
*& Objetivo  : Download (Servidor -> PC) e Upload (PC -> Servidor) dos
*&             arquivos de transporte de requests: cofile K<nnnnnn>.<SID>
*&             e data R<nnnnnn>.<SID>, substituindo o uso manual das
*&             transações CG3Y e CG3Z.
*& Plataforma: SAP ECC 7.4 / S/4HANA (ABAP OO - MVC)
*&---------------------------------------------------------------------*
*& Versão | Data       | Autor              | Descrição
*& 1.0    | 16/10/2026 | João Luís Medeiros | Download (ZQA_DOWNLOAD_REQUEST)
*& 1.1    | 16/10/2026 | João Luís Medeiros | Correção atividade S_DATASET
*& 2.0    | 16/10/2026 | João Luís Medeiros | Inclusão do modo Upload
*&---------------------------------------------------------------------*
REPORT zqa_transfer_request.

*----------------------------------------------------------------------*
* Tipos
*----------------------------------------------------------------------*
TYPES:
  ty_r_trkorr TYPE RANGE OF trkorr,

  BEGIN OF ty_request,
    trkorr     TYPE e070-trkorr,
    trfunction TYPE e070-trfunction,
    trstatus   TYPE e070-trstatus,
    as4user    TYPE e070-as4user,
    as4date    TYPE e070-as4date,
    as4text    TYPE e07t-as4text,
  END OF ty_request,
  ty_t_request TYPE STANDARD TABLE OF ty_request WITH DEFAULT KEY,

  BEGIN OF ty_texto,
    trkorr  TYPE e07t-trkorr,
    as4text TYPE e07t-as4text,
  END OF ty_texto,
  ty_t_texto TYPE SORTED TABLE OF ty_texto WITH UNIQUE KEY trkorr,

  BEGIN OF ty_log,
    status       TYPE icon_d,
    operacao     TYPE char10,
    trkorr       TYPE trkorr,
    as4text      TYPE as4text,
    tipo         TYPE char10,
    arq_servidor TYPE string,
    arq_local    TYPE string,
    tamanho      TYPE i,
    mensagem     TYPE string,
  END OF ty_log,
  ty_t_log TYPE STANDARD TABLE OF ty_log WITH DEFAULT KEY.

*----------------------------------------------------------------------*
* Tela de seleção
* (TABLES usado apenas como referência de tipo do SELECT-OPTIONS)
*----------------------------------------------------------------------*
TABLES e070.

SELECTION-SCREEN BEGIN OF BLOCK b0 WITH FRAME TITLE TEXT-003.
  PARAMETERS:
    p_down RADIOBUTTON GROUP mod DEFAULT 'X',
    p_up   RADIOBUTTON GROUP mod.
SELECTION-SCREEN END OF BLOCK b0.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  SELECT-OPTIONS so_trk FOR e070-trkorr OBLIGATORY NO INTERVALS.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
  PARAMETERS:
    p_pasta TYPE rlgrap-filename LOWER CASE OBLIGATORY,
    p_dirtr TYPE rlgrap-filename LOWER CASE OBLIGATORY,
    p_subp  AS CHECKBOX DEFAULT 'X',
    p_sobr  AS CHECKBOX DEFAULT ' '.
SELECTION-SCREEN END OF BLOCK b2.

*----------------------------------------------------------------------*
* Exceção local
*----------------------------------------------------------------------*
CLASS lcx_transfer DEFINITION INHERITING FROM cx_static_check FINAL.
  PUBLIC SECTION.
    DATA mv_texto TYPE string READ-ONLY.
    METHODS:
      constructor
        IMPORTING i_texto    TYPE string OPTIONAL
                  i_previous TYPE REF TO cx_root OPTIONAL,
      get_text REDEFINITION.
ENDCLASS.

CLASS lcx_transfer IMPLEMENTATION.
  METHOD constructor.
    super->constructor( previous = i_previous ).
    mv_texto = i_texto.
  ENDMETHOD.

  METHOD get_text.
    result = COND #( WHEN mv_texto IS NOT INITIAL THEN mv_texto
                     ELSE super->get_text( ) ).
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* MODEL - acesso a dados, servidor de aplicação e frontend
*----------------------------------------------------------------------*
CLASS lcl_model DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      m_obter_dir_trans
        RETURNING VALUE(r_dir) TYPE rlgrap-filename.

    METHODS:
      " --- Banco de dados ---
      m_buscar_requests
        IMPORTING i_r_trkorr         TYPE ty_r_trkorr
        RETURNING VALUE(r_t_request) TYPE ty_t_request,

      " --- Servidor de aplicação ---
      m_montar_caminho_servidor
        IMPORTING i_dir_trans      TYPE csequence
                  i_subdir         TYPE csequence
                  i_arquivo        TYPE csequence
        RETURNING VALUE(r_caminho) TYPE string,

      m_existe_arquivo_servidor
        IMPORTING i_caminho       TYPE string
        RETURNING VALUE(r_existe) TYPE abap_bool,

      m_ler_arquivo_servidor
        IMPORTING i_caminho         TYPE string
        RETURNING VALUE(r_conteudo) TYPE xstring
        RAISING   lcx_transfer,

      m_gravar_arquivo_servidor
        IMPORTING i_caminho  TYPE string
                  i_conteudo TYPE xstring
        RAISING   lcx_transfer,

      " --- Frontend (PC) ---
      m_obter_separador_local
        RETURNING VALUE(r_separador) TYPE string,

      m_garantir_pasta_local
        IMPORTING i_pasta TYPE string
        RAISING   lcx_transfer,

      m_existe_arquivo_local
        IMPORTING i_caminho       TYPE string
        RETURNING VALUE(r_existe) TYPE abap_bool,

      m_ler_arquivo_local
        IMPORTING i_caminho         TYPE string
        RETURNING VALUE(r_conteudo) TYPE xstring
        RAISING   lcx_transfer,

      m_gravar_arquivo_local
        IMPORTING i_caminho  TYPE string
                  i_conteudo TYPE xstring
        RAISING   lcx_transfer.

  PRIVATE SECTION.
    METHODS m_verificar_autorizacao
      IMPORTING i_caminho   TYPE string
                i_atividade TYPE csequence
                i_descricao TYPE string
      RAISING   lcx_transfer.
ENDCLASS.

CLASS lcl_model IMPLEMENTATION.
  METHOD m_obter_dir_trans.
    DATA: lv_nome  TYPE c LENGTH 60 VALUE 'DIR_TRANS',
          lv_valor TYPE c LENGTH 255.

    CALL 'C_SAPGPARAM' ID 'NAME'  FIELD lv_nome
                       ID 'VALUE' FIELD lv_valor.

    r_dir = COND #( WHEN lv_valor IS INITIAL THEN '/usr/sap/trans'
                    ELSE lv_valor ).
  ENDMETHOD.

  METHOD m_buscar_requests.
    DATA lt_texto TYPE ty_t_texto.

    " Somente requests (STRKORR vazio) - tarefas não geram arquivos
    SELECT trkorr, trfunction, trstatus, as4user, as4date
      FROM e070
      WHERE trkorr  IN @i_r_trkorr
        AND strkorr =  @space
      INTO CORRESPONDING FIELDS OF TABLE @r_t_request.

    IF r_t_request IS INITIAL.
      RETURN.
    ENDIF.

    SELECT trkorr, as4text
      FROM e07t
      FOR ALL ENTRIES IN @r_t_request
      WHERE trkorr = @r_t_request-trkorr
        AND langu  = @sy-langu
      INTO TABLE @lt_texto.

    LOOP AT r_t_request ASSIGNING FIELD-SYMBOL(<ls_request>).
      READ TABLE lt_texto INTO DATA(ls_texto)
           WITH TABLE KEY trkorr = <ls_request>-trkorr.
      IF sy-subrc = 0.
        <ls_request>-as4text = ls_texto-as4text.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD m_montar_caminho_servidor.
    DATA(lv_sep) = COND string( WHEN sy-opsys CS 'WIN' THEN `\` ELSE `/` ).
    DATA(lv_dir) = replace( val   = condense( CONV string( i_dir_trans ) )
                            regex = `[/\\]+$`
                            with  = `` ).

    r_caminho = |{ lv_dir }{ lv_sep }{ i_subdir }{ lv_sep }{ i_arquivo }|.
  ENDMETHOD.

  METHOD m_verificar_autorizacao.
    DATA: lv_programa TYPE authb-program,
          lv_arquivo  TYPE authb-filename.

    lv_programa = sy-repid.
    lv_arquivo  = i_caminho.

    CALL FUNCTION 'AUTHORITY_CHECK_DATASET'
      EXPORTING
        program          = lv_programa
        activity         = i_atividade
        filename         = lv_arquivo
      EXCEPTIONS
        no_authority     = 1
        activity_unknown = 2
        OTHERS           = 3.

    CASE sy-subrc.
      WHEN 0.
      WHEN 1.
        RAISE EXCEPTION TYPE lcx_transfer
          EXPORTING i_texto = |Sem autorização S_DATASET ({ i_descricao } / PROGRAM { lv_programa }) | &&
                              |para { i_caminho } - verifique a SU53|.
      WHEN 2.
        RAISE EXCEPTION TYPE lcx_transfer
          EXPORTING i_texto = |Atividade { i_atividade } desconhecida na verificação S_DATASET|.
      WHEN OTHERS.
        RAISE EXCEPTION TYPE lcx_transfer
          EXPORTING i_texto = |Erro { sy-subrc } na verificação S_DATASET para { i_caminho }|.
    ENDCASE.
  ENDMETHOD.

  METHOD m_existe_arquivo_servidor.
    r_existe = abap_false.

    TRY.
        OPEN DATASET i_caminho FOR INPUT IN BINARY MODE.
        IF sy-subrc = 0.
          r_existe = abap_true.
          CLOSE DATASET i_caminho.
        ENDIF.
      CATCH cx_sy_file_access_error.
        r_existe = abap_false.
    ENDTRY.
  ENDMETHOD.

  METHOD m_ler_arquivo_servidor.
    DATA lv_msg TYPE string.

    m_verificar_autorizacao( i_caminho   = i_caminho
                             i_atividade = sabc_act_read
                             i_descricao = `leitura` ).

    TRY.
        OPEN DATASET i_caminho FOR INPUT IN BINARY MODE MESSAGE lv_msg.
        IF sy-subrc <> 0.
          RAISE EXCEPTION TYPE lcx_transfer
            EXPORTING i_texto = |Arquivo não encontrado no servidor: { i_caminho } { lv_msg }|.
        ENDIF.

        " Em BINARY MODE com destino XSTRING o arquivo é lido por completo
        READ DATASET i_caminho INTO r_conteudo.
        CLOSE DATASET i_caminho.

      CATCH cx_sy_file_access_error INTO DATA(lx_arquivo).
        CLOSE DATASET i_caminho.
        RAISE EXCEPTION TYPE lcx_transfer
          EXPORTING i_texto    = lx_arquivo->get_text( )
                    i_previous = lx_arquivo.
    ENDTRY.

    IF r_conteudo IS INITIAL.
      RAISE EXCEPTION TYPE lcx_transfer
        EXPORTING i_texto = |Arquivo vazio no servidor: { i_caminho }|.
    ENDIF.
  ENDMETHOD.

  METHOD m_gravar_arquivo_servidor.
    DATA lv_msg TYPE string.

    m_verificar_autorizacao( i_caminho   = i_caminho
                             i_atividade = sabc_act_write
                             i_descricao = `gravação` ).

    TRY.
        OPEN DATASET i_caminho FOR OUTPUT IN BINARY MODE MESSAGE lv_msg.
        IF sy-subrc <> 0.
          RAISE EXCEPTION TYPE lcx_transfer
            EXPORTING i_texto = |Não foi possível gravar no servidor: { i_caminho } { lv_msg }|.
        ENDIF.

        TRANSFER i_conteudo TO i_caminho.
        CLOSE DATASET i_caminho.

      CATCH cx_sy_file_access_error INTO DATA(lx_arquivo).
        CLOSE DATASET i_caminho.
        RAISE EXCEPTION TYPE lcx_transfer
          EXPORTING i_texto    = lx_arquivo->get_text( )
                    i_previous = lx_arquivo.
    ENDTRY.
  ENDMETHOD.

  METHOD m_obter_separador_local.
    DATA lv_sep TYPE c LENGTH 1.

    cl_gui_frontend_services=>get_file_separator(
      CHANGING  file_separator = lv_sep
      EXCEPTIONS OTHERS        = 1 ).
    cl_gui_cfw=>flush( ).

    r_separador = COND #( WHEN lv_sep IS INITIAL THEN `\` ELSE lv_sep ).
  ENDMETHOD.

  METHOD m_garantir_pasta_local.
    DATA: lv_existe TYPE abap_bool,
          lv_rc     TYPE i.

    cl_gui_frontend_services=>directory_exist(
      EXPORTING  directory = i_pasta
      RECEIVING  result    = lv_existe
      EXCEPTIONS OTHERS    = 1 ).

    IF lv_existe = abap_true.
      RETURN.
    ENDIF.

    cl_gui_frontend_services=>directory_create(
      EXPORTING  directory = i_pasta
      CHANGING   rc        = lv_rc
      EXCEPTIONS OTHERS    = 1 ).
    IF sy-subrc <> 0 OR lv_rc <> 0.
      RAISE EXCEPTION TYPE lcx_transfer
        EXPORTING i_texto = |Não foi possível criar a pasta local { i_pasta }|.
    ENDIF.
  ENDMETHOD.

  METHOD m_existe_arquivo_local.
    cl_gui_frontend_services=>file_exist(
      EXPORTING  file   = i_caminho
      RECEIVING  result = r_existe
      EXCEPTIONS OTHERS = 1 ).
    IF sy-subrc <> 0.
      r_existe = abap_false.
    ENDIF.
  ENDMETHOD.

  METHOD m_ler_arquivo_local.
    DATA: lt_binario TYPE solix_tab,
          lv_tamanho TYPE i.

    cl_gui_frontend_services=>gui_upload(
      EXPORTING  filename   = i_caminho
                 filetype   = 'BIN'
      IMPORTING  filelength = lv_tamanho
      CHANGING   data_tab   = lt_binario
      EXCEPTIONS OTHERS     = 1 ).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE lcx_transfer
        EXPORTING i_texto = |Erro ao ler o arquivo no PC: { i_caminho }|.
    ENDIF.

    IF lv_tamanho = 0.
      RAISE EXCEPTION TYPE lcx_transfer
        EXPORTING i_texto = |Arquivo vazio no PC: { i_caminho }|.
    ENDIF.

    r_conteudo = cl_bcs_convert=>solix_to_xstring( it_solix = lt_binario
                                                    iv_size  = lv_tamanho ).
  ENDMETHOD.

  METHOD m_gravar_arquivo_local.
    DATA(lt_binario) = cl_bcs_convert=>xstring_to_solix( iv_xstring = i_conteudo ).
    DATA(lv_tamanho) = xstrlen( i_conteudo ).

    cl_gui_frontend_services=>gui_download(
      EXPORTING  bin_filesize = lv_tamanho
                 filename     = i_caminho
                 filetype     = 'BIN'
      CHANGING   data_tab     = lt_binario
      EXCEPTIONS OTHERS       = 1 ).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE lcx_transfer
        EXPORTING i_texto = |Erro ao gravar no PC: { i_caminho }|.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* VIEW - F4, mensagens e log ALV
*----------------------------------------------------------------------*
CLASS lcl_view DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      m_f4_pasta_local
        IMPORTING i_pasta_atual  TYPE rlgrap-filename
        RETURNING VALUE(r_pasta) TYPE rlgrap-filename.

    METHODS:
      m_exibir_log  IMPORTING i_t_log  TYPE ty_t_log
                              i_titulo TYPE string,
      m_msg_sucesso IMPORTING i_texto  TYPE string,
      m_msg_erro    IMPORTING i_texto  TYPE string,
      m_msg_aviso   IMPORTING i_texto  TYPE string.

  PRIVATE SECTION.
    DATA mt_log TYPE ty_t_log.
    METHODS m_configurar_colunas
      IMPORTING i_o_salv TYPE REF TO cl_salv_table.
ENDCLASS.

CLASS lcl_view IMPLEMENTATION.
  METHOD m_f4_pasta_local.
    DATA lv_pasta TYPE string.

    r_pasta = i_pasta_atual.

    cl_gui_frontend_services=>directory_browse(
      EXPORTING  window_title    = 'Selecione a pasta no PC'
                 initial_folder  = CONV #( i_pasta_atual )
      CHANGING   selected_folder = lv_pasta
      EXCEPTIONS OTHERS          = 1 ).
    cl_gui_cfw=>flush( ).

    IF sy-subrc = 0 AND lv_pasta IS NOT INITIAL.
      r_pasta = lv_pasta.
    ENDIF.
  ENDMETHOD.

  METHOD m_exibir_log.
    mt_log = i_t_log.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = DATA(lo_salv)
          CHANGING  t_table      = mt_log ).

        lo_salv->get_functions( )->set_all( abap_true ).
        lo_salv->get_display_settings( )->set_striped_pattern( abap_true ).
        lo_salv->get_display_settings( )->set_list_header( CONV #( i_titulo ) ).
        m_configurar_colunas( lo_salv ).

        lo_salv->display( ).

      CATCH cx_salv_msg INTO DATA(lx_salv).
        m_msg_erro( lx_salv->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD m_configurar_colunas.
    TYPES: BEGIN OF ty_coluna,
             nome  TYPE lvc_fname,
             texto TYPE scrtext_l,
           END OF ty_coluna,
           ty_t_coluna TYPE STANDARD TABLE OF ty_coluna WITH DEFAULT KEY.

    DATA(lo_colunas) = i_o_salv->get_columns( ).
    lo_colunas->set_optimize( abap_true ).

    DATA(lt_coluna) = VALUE ty_t_coluna(
      ( nome = 'STATUS'       texto = 'Status' )
      ( nome = 'OPERACAO'     texto = 'Operação' )
      ( nome = 'TRKORR'       texto = 'Request' )
      ( nome = 'AS4TEXT'      texto = 'Descrição' )
      ( nome = 'TIPO'         texto = 'Tipo' )
      ( nome = 'ARQ_SERVIDOR' texto = 'Arquivo no servidor' )
      ( nome = 'ARQ_LOCAL'    texto = 'Arquivo no PC' )
      ( nome = 'TAMANHO'      texto = 'Tamanho (bytes)' )
      ( nome = 'MENSAGEM'     texto = 'Mensagem' ) ).

    LOOP AT lt_coluna INTO DATA(ls_coluna).
      TRY.
          DATA(lo_coluna) = lo_colunas->get_column( ls_coluna-nome ).
          lo_coluna->set_long_text( ls_coluna-texto ).
          lo_coluna->set_medium_text( CONV #( ls_coluna-texto ) ).
          lo_coluna->set_short_text( CONV #( ls_coluna-texto ) ).
        CATCH cx_salv_not_found.
          CONTINUE.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

  METHOD m_msg_sucesso.
    MESSAGE i_texto TYPE 'S'.
  ENDMETHOD.

  METHOD m_msg_erro.
    MESSAGE i_texto TYPE 'S' DISPLAY LIKE 'E'.
  ENDMETHOD.

  METHOD m_msg_aviso.
    MESSAGE i_texto TYPE 'S' DISPLAY LIKE 'W'.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* CONTROLLER - orquestração e regras
*----------------------------------------------------------------------*
CLASS lcl_controller DEFINITION FINAL.
  PUBLIC SECTION.
    CONSTANTS:
      gc_op_download TYPE char10 VALUE 'DOWNLOAD',
      gc_op_upload   TYPE char10 VALUE 'UPLOAD',
      gc_tipo_cofile TYPE char10 VALUE 'COFILE',
      gc_tipo_data   TYPE char10 VALUE 'DATA'.

    METHODS:
      constructor,
      m_executar.

  PRIVATE SECTION.
    DATA: mo_model    TYPE REF TO lcl_model,
          mo_view     TYPE REF TO lcl_view,
          mt_log      TYPE ty_t_log,
          mv_operacao TYPE char10,
          mv_sep_pc   TYPE string.

    METHODS:
      m_validar_selecao
        RETURNING VALUE(r_ok) TYPE abap_bool,

      m_processar_download,

      m_processar_upload,

      m_registrar_nao_encontradas
        IMPORTING i_t_request TYPE ty_t_request,

      m_processar_request
        IMPORTING i_s_request TYPE ty_request,

      m_transferir_arquivo
        IMPORTING i_s_request    TYPE ty_request
                  i_tipo         TYPE char10
                  i_subdir       TYPE string
                  i_arquivo      TYPE string
                  i_pasta        TYPE string
        RETURNING VALUE(r_s_log) TYPE ty_log,

      m_baixar_arquivo
        CHANGING ch_s_log TYPE ty_log,

      m_enviar_arquivo
        CHANGING ch_s_log TYPE ty_log,

      m_adicionar_erro
        IMPORTING i_s_request TYPE ty_request
                  i_mensagem  TYPE string,

      m_finalizar.
ENDCLASS.

CLASS lcl_controller IMPLEMENTATION.
  METHOD constructor.
    mo_model    = NEW lcl_model( ).
    mo_view     = NEW lcl_view( ).
    mv_operacao = COND #( WHEN p_up = abap_true THEN gc_op_upload
                          ELSE gc_op_download ).
  ENDMETHOD.

  METHOD m_executar.
    IF m_validar_selecao( ) = abap_false.
      RETURN.
    ENDIF.

    mv_sep_pc = mo_model->m_obter_separador_local( ).

    CASE mv_operacao.
      WHEN gc_op_download.
        m_processar_download( ).
      WHEN gc_op_upload.
        m_processar_upload( ).
    ENDCASE.
  ENDMETHOD.

  METHOD m_validar_selecao.
    r_ok = abap_false.

    IF sy-batch = abap_true.
      mo_view->m_msg_erro( `Transferência com o PC não é possível em background. Execute em diálogo.` ).
      RETURN.
    ENDIF.

    IF so_trk[] IS INITIAL.
      mo_view->m_msg_erro( `Informe ao menos uma request.` ).
      RETURN.
    ENDIF.

    IF p_pasta IS INITIAL.
      mo_view->m_msg_erro( `Informe a pasta no PC.` ).
      RETURN.
    ENDIF.

    r_ok = abap_true.
  ENDMETHOD.

  METHOD m_processar_download.
    " Download: request precisa existir e estar liberada neste sistema
    DATA(lt_request) = mo_model->m_buscar_requests( i_r_trkorr = so_trk[] ).
    m_registrar_nao_encontradas( lt_request ).

    LOOP AT lt_request INTO DATA(ls_request).
      " R = Liberada | N = Liberada (com proteção de importação)
      IF ls_request-trstatus NA 'RN'.
        m_adicionar_erro( i_s_request = ls_request
                          i_mensagem  = |Request não liberada (status { ls_request-trstatus }) | &&
                                        |- arquivos ainda não foram gerados| ).
        CONTINUE.
      ENDIF.
      m_processar_request( ls_request ).
    ENDLOOP.

    m_finalizar( ).
  ENDMETHOD.

  METHOD m_processar_upload.
    " Upload: a request ainda não existe no sistema destino (vem de outro
    " ambiente), por isso os dados são montados direto da tela
    DATA(lt_request) = VALUE ty_t_request(
      FOR ls_trk IN so_trk[] WHERE ( sign = 'I' AND option = 'EQ' )
      ( trkorr = ls_trk-low ) ).

    LOOP AT lt_request INTO DATA(ls_request).
      m_processar_request( ls_request ).
    ENDLOOP.

    m_finalizar( ).
  ENDMETHOD.

  METHOD m_registrar_nao_encontradas.
    LOOP AT so_trk INTO DATA(ls_trk) WHERE sign = 'I' AND option = 'EQ'.
      IF NOT line_exists( i_t_request[ trkorr = ls_trk-low ] ).
        m_adicionar_erro( i_s_request = VALUE #( trkorr = ls_trk-low )
                          i_mensagem  = `Request não encontrada na E070 ou é uma tarefa` ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD m_processar_request.
    " Formato esperado: <SID>K<numero>  ex.: DEVK900123
    IF strlen( i_s_request-trkorr ) < 5 OR i_s_request-trkorr+3(1) <> 'K'.
      m_adicionar_erro( i_s_request = i_s_request
                        i_mensagem  = `Formato de request inválido (esperado <SID>K<número>)` ).
      RETURN.
    ENDIF.

    DATA(lv_sid)    = CONV string( i_s_request-trkorr(3) ).
    DATA(lv_numero) = condense( CONV string( i_s_request-trkorr+4 ) ).
    DATA(lv_pasta)  = replace( val   = condense( CONV string( p_pasta ) )
                               regex = `[/\\]+$`
                               with  = `` ).

    IF p_subp = abap_true.
      lv_pasta = |{ lv_pasta }{ mv_sep_pc }{ i_s_request-trkorr }|.
    ENDIF.

    " Pasta local só precisa ser criada no download
    IF mv_operacao = gc_op_download.
      TRY.
          mo_model->m_garantir_pasta_local( lv_pasta ).
        CATCH lcx_transfer INTO DATA(lx_pasta).
          m_adicionar_erro( i_s_request = i_s_request
                            i_mensagem  = lx_pasta->get_text( ) ).
          RETURN.
      ENDTRY.
    ENDIF.

    DATA(ls_log_cofile) = m_transferir_arquivo( i_s_request = i_s_request
                                                i_tipo      = gc_tipo_cofile
                                                i_subdir    = `cofiles`
                                                i_arquivo   = |K{ lv_numero }.{ lv_sid }|
                                                i_pasta     = lv_pasta ).
    APPEND ls_log_cofile TO mt_log.

    DATA(ls_log_data) = m_transferir_arquivo( i_s_request = i_s_request
                                              i_tipo      = gc_tipo_data
                                              i_subdir    = `data`
                                              i_arquivo   = |R{ lv_numero }.{ lv_sid }|
                                              i_pasta     = lv_pasta ).
    APPEND ls_log_data TO mt_log.
  ENDMETHOD.

  METHOD m_transferir_arquivo.
    r_s_log = VALUE #(
      operacao     = mv_operacao
      trkorr       = i_s_request-trkorr
      as4text      = i_s_request-as4text
      tipo         = i_tipo
      arq_servidor = mo_model->m_montar_caminho_servidor( i_dir_trans = p_dirtr
                                                          i_subdir    = i_subdir
                                                          i_arquivo   = i_arquivo )
      arq_local    = |{ i_pasta }{ mv_sep_pc }{ i_arquivo }| ).

    CASE mv_operacao.
      WHEN gc_op_download.
        m_baixar_arquivo( CHANGING ch_s_log = r_s_log ).
      WHEN gc_op_upload.
        m_enviar_arquivo( CHANGING ch_s_log = r_s_log ).
    ENDCASE.
  ENDMETHOD.

  METHOD m_baixar_arquivo.
    IF p_sobr = abap_false
       AND mo_model->m_existe_arquivo_local( ch_s_log-arq_local ) = abap_true.
      ch_s_log-status   = icon_led_yellow.
      ch_s_log-mensagem = `Arquivo já existe no PC - marque "Sobrescrever" para substituir`.
      RETURN.
    ENDIF.

    TRY.
        DATA(lv_conteudo) = mo_model->m_ler_arquivo_servidor( ch_s_log-arq_servidor ).
        mo_model->m_gravar_arquivo_local( i_caminho  = ch_s_log-arq_local
                                          i_conteudo = lv_conteudo ).
        ch_s_log-status   = icon_led_green.
        ch_s_log-tamanho  = xstrlen( lv_conteudo ).
        ch_s_log-mensagem = `Download realizado com sucesso`.

      CATCH lcx_transfer INTO DATA(lx_transfer).
        ch_s_log-status   = icon_led_red.
        ch_s_log-mensagem = lx_transfer->get_text( ).
    ENDTRY.
  ENDMETHOD.

  METHOD m_enviar_arquivo.
    IF mo_model->m_existe_arquivo_local( ch_s_log-arq_local ) = abap_false.
      ch_s_log-status   = icon_led_red.
      ch_s_log-mensagem = `Arquivo não encontrado no PC`.
      RETURN.
    ENDIF.

    IF p_sobr = abap_false
       AND mo_model->m_existe_arquivo_servidor( ch_s_log-arq_servidor ) = abap_true.
      ch_s_log-status   = icon_led_yellow.
      ch_s_log-mensagem = `Arquivo já existe no servidor - marque "Sobrescrever" para substituir`.
      RETURN.
    ENDIF.

    TRY.
        DATA(lv_conteudo) = mo_model->m_ler_arquivo_local( ch_s_log-arq_local ).
        mo_model->m_gravar_arquivo_servidor( i_caminho  = ch_s_log-arq_servidor
                                             i_conteudo = lv_conteudo ).
        ch_s_log-status   = icon_led_green.
        ch_s_log-tamanho  = xstrlen( lv_conteudo ).
        ch_s_log-mensagem = `Upload realizado com sucesso`.

      CATCH lcx_transfer INTO DATA(lx_transfer).
        ch_s_log-status   = icon_led_red.
        ch_s_log-mensagem = lx_transfer->get_text( ).
    ENDTRY.
  ENDMETHOD.

  METHOD m_adicionar_erro.
    APPEND VALUE #( status   = icon_led_red
                    operacao = mv_operacao
                    trkorr   = i_s_request-trkorr
                    as4text  = i_s_request-as4text
                    mensagem = i_mensagem ) TO mt_log.
  ENDMETHOD.

  METHOD m_finalizar.
    IF mt_log IS INITIAL.
      mo_view->m_msg_aviso( `Nenhuma request processada.` ).
      RETURN.
    ENDIF.

    DATA(lv_ok)   = REDUCE i( INIT n = 0 FOR ls IN mt_log
                              WHERE ( status = icon_led_green ) NEXT n = n + 1 ).
    DATA(lv_erro) = lines( mt_log ) - lv_ok.
    DATA(lv_acao) = COND string( WHEN mv_operacao = gc_op_upload THEN `enviado(s) ao servidor`
                                 ELSE `baixado(s) para o PC` ).

    IF lv_erro = 0.
      mo_view->m_msg_sucesso( |{ lv_ok } arquivo(s) { lv_acao } com sucesso.| ).
    ELSE.
      mo_view->m_msg_aviso( |{ lv_ok } arquivo(s) { lv_acao }, { lv_erro } com pendência. Verifique o log.| ).
    ENDIF.

    mo_view->m_exibir_log(
      i_t_log  = mt_log
      i_titulo = COND #( WHEN mv_operacao = gc_op_upload
                         THEN `Upload de arquivos de transporte (PC -> Servidor)`
                         ELSE `Download de arquivos de transporte (Servidor -> PC)` ) ).
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* Eventos
*----------------------------------------------------------------------*
INITIALIZATION.
  p_dirtr = lcl_model=>m_obter_dir_trans( ).

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_pasta.
  p_pasta = lcl_view=>m_f4_pasta_local( p_pasta ).

START-OF-SELECTION.
  DATA(lo_controller) = NEW lcl_controller( ).
  lo_controller->m_executar( ).

*----------------------------------------------------------------------*
* Elementos de texto (SE38 > Ir para > Elementos de texto)
*----------------------------------------------------------------------*
* Símbolos de texto:
*   001  Requests de transporte
*   002  Pasta e opções
*   003  Operação
*
* Textos de seleção:
*   P_DOWN  Download (Servidor -> PC)
*   P_UP    Upload (PC -> Servidor)
*   SO_TRK  Request(s)
*   P_PASTA Pasta no PC
*   P_DIRTR Diretório de transporte (servidor)
*   P_SUBP  Subpasta por request
*   P_SOBR  Sobrescrever arquivos existentes
*----------------------------------------------------------------------*
