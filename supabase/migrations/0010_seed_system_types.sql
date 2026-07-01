-- IT Brain — 0010: Seed de arquetipos y tipos de sistema
-- Ver docs/03-modelo-entidades-relaciones.md §2, docs/06-casos-de-uso.md UC-05
--
-- Tipos de sistema (org_id IS NULL, is_system = true): visibles para toda
-- organización, no editables por el cliente (solo Admin puede DERIVAR uno
-- propio, no modificar estos). IDs fijos y legibles para facilitar referencias
-- desde datos de ejemplo/tests.

insert into entity_types (id, org_id, key, name, archetype, is_system) values
  -- device
  ('00000000-0000-0000-0000-000000000001', null, 'pos',            'POS',              'device', true),
  ('00000000-0000-0000-0000-000000000002', null, 'servidor',       'Servidor',         'device', true),
  ('00000000-0000-0000-0000-000000000003', null, 'switch',         'Switch',           'device', true),
  ('00000000-0000-0000-0000-000000000004', null, 'router',         'Router',           'device', true),
  ('00000000-0000-0000-0000-000000000005', null, 'firewall',       'Firewall',         'device', true),
  ('00000000-0000-0000-0000-000000000006', null, 'access_point',   'Access Point',     'device', true),
  ('00000000-0000-0000-0000-000000000007', null, 'impresora',      'Impresora',        'device', true),
  ('00000000-0000-0000-0000-000000000008', null, 'ups',            'UPS',              'device', true),
  ('00000000-0000-0000-0000-000000000009', null, 'camara',         'Cámara',           'device', true),
  ('00000000-0000-0000-0000-000000000010', null, 'telefono_ip',    'Teléfono IP',      'device', true),
  ('00000000-0000-0000-0000-000000000011', null, 'tablet',         'Tablet',           'device', true),
  ('00000000-0000-0000-0000-000000000012', null, 'celular',        'Celular',          'device', true),
  ('00000000-0000-0000-0000-000000000013', null, 'monitor',        'Monitor',          'device', true),
  -- network
  ('00000000-0000-0000-0000-000000000020', null, 'vlan',           'VLAN',             'network', true),
  ('00000000-0000-0000-0000-000000000021', null, 'red',            'Red',              'network', true),
  ('00000000-0000-0000-0000-000000000022', null, 'puerto',         'Puerto',           'network', true),
  ('00000000-0000-0000-0000-000000000023', null, 'dominio',        'Dominio',          'network', true),
  -- software
  ('00000000-0000-0000-0000-000000000030', null, 'sistema',        'Sistema',          'software', true),
  ('00000000-0000-0000-0000-000000000031', null, 'servicio',       'Servicio',         'software', true),
  ('00000000-0000-0000-0000-000000000032', null, 'base_de_datos',  'Base de Datos',    'software', true),
  ('00000000-0000-0000-0000-000000000033', null, 'aplicacion',     'Aplicación',       'software', true),
  -- license
  ('00000000-0000-0000-0000-000000000040', null, 'licencia',       'Licencia',         'license', true),
  -- credential
  ('00000000-0000-0000-0000-000000000050', null, 'credencial',     'Credencial',       'credential', true),
  -- identity
  ('00000000-0000-0000-0000-000000000060', null, 'usuario',        'Usuario',          'identity', true),
  ('00000000-0000-0000-0000-000000000061', null, 'rol',            'Rol',              'identity', true),
  -- location
  ('00000000-0000-0000-0000-000000000070', null, 'sede',           'Sede',             'location', true),
  ('00000000-0000-0000-0000-000000000071', null, 'oficina',        'Oficina',          'location', true),
  ('00000000-0000-0000-0000-000000000072', null, 'rack',           'Rack',             'location', true),
  -- party
  ('00000000-0000-0000-0000-000000000080', null, 'proveedor',      'Proveedor',        'party', true),
  ('00000000-0000-0000-0000-000000000081', null, 'cliente',        'Cliente',          'party', true),
  -- knowledge
  ('00000000-0000-0000-0000-000000000090', null, 'procedimiento',  'Procedimiento',    'knowledge', true),
  ('00000000-0000-0000-0000-000000000091', null, 'manual',         'Manual',           'knowledge', true),
  ('00000000-0000-0000-0000-000000000092', null, 'solucion',       'Solución',         'knowledge', true),
  ('00000000-0000-0000-0000-000000000093', null, 'problema_frecuente', 'Problema Frecuente', 'knowledge', true),
  -- case
  ('00000000-0000-0000-0000-000000000100', null, 'incidente',      'Incidente',        'case', true),
  ('00000000-0000-0000-0000-000000000101', null, 'problema',       'Problema',         'case', true),
  ('00000000-0000-0000-0000-000000000102', null, 'proyecto',       'Proyecto',         'case', true);

-- Campos representativos por tipo (demuestra el meta-modelo, docs 03 §4).
-- No exhaustivo: el resto de campos se añade desde configuración por el Admin (UC-05).

-- POS
insert into field_definitions (entity_type_id, key, label, data_type, is_searchable, sort_order) values
  ('00000000-0000-0000-0000-000000000001', 'serial', 'Serial', 'text', true, 1),
  ('00000000-0000-0000-0000-000000000001', 'ip', 'Dirección IP', 'ip', true, 2),
  ('00000000-0000-0000-0000-000000000001', 'modelo', 'Modelo', 'text', true, 3);

-- Servidor
insert into field_definitions (entity_type_id, key, label, data_type, is_searchable, sort_order) values
  ('00000000-0000-0000-0000-000000000002', 'ip', 'Dirección IP', 'ip', true, 1),
  ('00000000-0000-0000-0000-000000000002', 'sistema_operativo', 'Sistema Operativo', 'text', true, 2),
  ('00000000-0000-0000-0000-000000000002', 'ram_gb', 'RAM (GB)', 'number', false, 3);

-- Switch
insert into field_definitions (entity_type_id, key, label, data_type, is_searchable, sort_order) values
  ('00000000-0000-0000-0000-000000000003', 'ip', 'Dirección IP', 'ip', true, 1),
  ('00000000-0000-0000-0000-000000000003', 'puertos_totales', 'Puertos totales', 'number', false, 2);

-- Impresora
insert into field_definitions (entity_type_id, key, label, data_type, is_searchable, sort_order) values
  ('00000000-0000-0000-0000-000000000007', 'ip', 'Dirección IP', 'ip', true, 1),
  ('00000000-0000-0000-0000-000000000007', 'marca', 'Marca', 'text', true, 2),
  ('00000000-0000-0000-0000-000000000007', 'modelo', 'Modelo', 'text', true, 3);

-- Licencia
insert into field_definitions (entity_type_id, key, label, data_type, is_searchable, sort_order) values
  ('00000000-0000-0000-0000-000000000040', 'tipo', 'Tipo de licencia', 'text', true, 1),
  ('00000000-0000-0000-0000-000000000040', 'asientos', 'Asientos', 'number', false, 2),
  ('00000000-0000-0000-0000-000000000040', 'fecha_expiracion', 'Fecha de expiración', 'date', false, 3);

-- Credencial (el caso especial de seguridad — docs 05 §7, 04 §5)
insert into field_definitions (entity_type_id, key, label, data_type, is_searchable, sensitivity, min_role_read, sort_order) values
  ('00000000-0000-0000-0000-000000000050', 'usuario', 'Usuario', 'text', true, 'normal', 'consulta', 1),
  ('00000000-0000-0000-0000-000000000050', 'url', 'URL', 'url', true, 'normal', 'consulta', 2),
  ('00000000-0000-0000-0000-000000000050', 'fecha_expiracion', 'Expira', 'date', false, 'normal', 'consulta', 3);
-- El secreto en sí NO vive aquí: vive en la tabla `secrets` (0008), nunca en `entities.data`.

-- Incidente
insert into field_definitions (entity_type_id, key, label, data_type, is_searchable, options, sort_order) values
  ('00000000-0000-0000-0000-000000000100', 'prioridad', 'Prioridad', 'enum', true,
    '["baja","media","alta","critica"]'::jsonb, 1);
insert into field_definitions (entity_type_id, key, label, data_type, is_searchable, sort_order) values
  ('00000000-0000-0000-0000-000000000100', 'diagnostico', 'Diagnóstico', 'text', true, 2),
  ('00000000-0000-0000-0000-000000000100', 'causa', 'Causa', 'text', true, 3),
  ('00000000-0000-0000-0000-000000000100', 'solucion', 'Solución', 'text', true, 4),
  ('00000000-0000-0000-0000-000000000100', 'tiempo_resolucion_seg', 'Tiempo de resolución (seg)', 'number', false, 5);

-- Procedimiento
insert into field_definitions (entity_type_id, key, label, data_type, is_searchable, options, sort_order) values
  ('00000000-0000-0000-0000-000000000090', 'dificultad', 'Dificultad', 'enum', false,
    '["baja","media","alta"]'::jsonb, 1);
insert into field_definitions (entity_type_id, key, label, data_type, is_searchable, sort_order) values
  ('00000000-0000-0000-0000-000000000090', 'objetivo', 'Objetivo', 'text', true, 2),
  ('00000000-0000-0000-0000-000000000090', 'tiempo_estimado_min', 'Tiempo estimado (min)', 'number', false, 3);

-- Tipos de relación de sistema representativos (docs 03 §5)
insert into relationship_types (org_id, key, name, inverse_name) values
  (null, 'usa',              'usa',                'usado_por'),
  (null, 'depende_de',       'depende de',         'da servicio a'),
  (null, 'conectado_a',      'conectado a',        'conecta con'),
  (null, 'ubicado_en',       'ubicado en',         'aloja'),
  (null, 'ejecuta',          'ejecuta',            'ejecutado por'),
  (null, 'licenciado_por',   'licenciado por',     'licencia a'),
  (null, 'documentado_por',  'documentado por',    'documenta'),
  (null, 'resuelto_por',     'resuelto por',       'resuelve'),
  (null, 'afecta_a',         'afecta a',           'afectado por'),
  (null, 'suministrado_por', 'suministrado por',   'suministra'),
  (null, 'similar_a',        'similar a',          'similar a');
