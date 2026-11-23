-- Business rules kept as data, so they can be reviewed and changed without touching code.
-- Dimensions re-apply them on every run. Re-running setup keeps edits to existing rules.

-- Category group by code prefix; the longest matching prefix wins.
-- Codes follow a family scheme: 1011 American whiskey, 1022 tequila, 1031/1032 vodka...
CREATE TABLE IF NOT EXISTS core.category_group_rule (
    code_prefix    text PRIMARY KEY,
    category_group text NOT NULL
);

INSERT INTO core.category_group_rule (code_prefix, category_group) VALUES
    ('1011',  'American whiskey'),
    ('10121', 'Canadian whisky'),
    ('10122', 'Scotch'),
    ('10123', 'Scotch'),
    ('10124', 'Irish whiskey'),
    ('1012',  'Other imported whisky'),
    ('1022',  'Tequila and mezcal'),
    ('1031',  'Vodka'),
    ('1032',  'Vodka'),
    ('1041',  'Gin'),
    ('1042',  'Gin'),
    ('1051',  'Brandy'),
    ('1052',  'Brandy'),
    ('1062',  'Rum'),
    ('1071',  'Cocktails and RTD'),
    ('1081',  'Liqueurs and schnapps'),
    ('1082',  'Liqueurs and schnapps'),
    ('1091',  'Neutral and specialty spirits'),
    ('1092',  'Neutral and specialty spirits'),
    ('1701',  'Gift and seasonal packs'),
    ('1901',  'Special orders')
ON CONFLICT (code_prefix) DO NOTHING;

-- Store chain and type from the store name; the lowest priority number that matches wins.
-- Rules with chain NULL describe independents. Patterns are SQL LIKE on the upper-cased name.
CREATE TABLE IF NOT EXISTS core.store_type_rule (
    priority     int  PRIMARY KEY,
    name_pattern text NOT NULL,
    chain        text,
    store_type   text NOT NULL
);

INSERT INTO core.store_type_rule (priority, name_pattern, chain, store_type) VALUES
    (10,  '%/ BDI /%',              'Hy-Vee',        'Warehouse'),
    (20,  'HY-VEE WINE%',           'Hy-Vee',        'Liquor and tobacco'),
    (21,  'HY-VEE GAS%',            'Hy-Vee',        'Convenience'),
    (22,  'HY-VEE C-STORE%',        'Hy-Vee',        'Convenience'),
    (23,  'HY-VEE FAST%',           'Hy-Vee',        'Convenience'),
    (24,  'HY-VEE%DRUG%',           'Hy-Vee',        'Grocery'),
    (25,  'HY-VEE%',                'Hy-Vee',        'Grocery'),
    (30,  'CASEY''S%',              'Casey''s',      'Convenience'),
    (31,  'KUM & GO%',              'Kum & Go',      'Convenience'),
    (32,  'MAVERIK%',               'Maverik',       'Convenience'),
    (33,  'KWIK STAR%',             'Kwik Trip',     'Convenience'),
    (34,  'KWIK SHOP%',             'Kwik Trip',     'Convenience'),
    (35,  'QUIK TRIP%',             'QuikTrip',      'Convenience'),
    (36,  'QUIKTRIP%',              'QuikTrip',      'Convenience'),
    (37,  'CIRCLE K%',              'Circle K',      'Convenience'),
    (38,  'MEGA SAVER%',            'Mega Saver',    'Convenience'),
    (39,  'FAS MART%',              'Fas Mart',      'Convenience'),
    (40,  'FAREWAY%',               'Fareway',       'Grocery'),
    (41,  'HOMETOWN FOODS%',        'Hometown Foods','Grocery'),
    (42,  'SUNSHINE FOODS%',        'Sunshine Foods','Grocery'),
    (50,  'WALGREENS%',             'Walgreens',     'Pharmacy'),
    (51,  'CVS%',                   'CVS',           'Pharmacy'),
    (60,  'COSTCO%',                'Costco',        'Club and big box'),
    (61,  'SAM''S CLUB%',           'Sam''s Club',   'Club and big box'),
    (62,  'WAL-MART%',              'Walmart',       'Club and big box'),
    (63,  'WALMART%',               'Walmart',       'Club and big box'),
    (64,  'TARGET%',                'Target',        'Club and big box'),
    (65,  'SUPER TARGET%',          'Target',        'Club and big box'),
    (70,  'SMOKIN'' JOE''S%',       'Smokin'' Joe''s','Liquor and tobacco'),
    (71,  'BREW %',                 'Brew',          'Convenience'),
    (72,  'BREW',                   'Brew',          'Convenience'),
    (73,  'OSCO%',                  'Osco',          'Pharmacy'),
    (74,  'PRICE CHOPPER%',         'Price Chopper', 'Grocery'),
    (75,  'CASH SAVER%',            'Cash Saver',    'Grocery'),
    (76,  'FAMILY FARE%',           'Family Fare',   'Grocery'),
    (77,  'BEER THIRTY%',           'Beer Thirty',   'Liquor and tobacco'),
    (90,  '%DISTRIBUT%',            NULL,            'Warehouse'),
    (91,  '%CASINO%',               NULL,            'Other'),
    -- Independents by keyword
    (100, '%LIQUOR%',               NULL,            'Liquor and tobacco'),
    (101, '%SPIRITS%',              NULL,            'Liquor and tobacco'),
    (102, '%WINE%',                 NULL,            'Liquor and tobacco'),
    (103, '%TOBACCO%',              NULL,            'Liquor and tobacco'),
    (107, '%BWS%',                  NULL,            'Liquor and tobacco'),
    (108, '%BEVERAGE%',             NULL,            'Liquor and tobacco'),
    (109, '%BOTTLE%',               NULL,            'Liquor and tobacco'),
    (104, '%SMOKE%',                NULL,            'Liquor and tobacco'),
    (105, '%CIGAR%',                NULL,            'Liquor and tobacco'),
    (106, '%VAPOR%',                NULL,            'Liquor and tobacco'),
    (110, '%DRUG%',                 NULL,            'Pharmacy'),
    (111, '%PHARMACY%',             NULL,            'Pharmacy'),
    (115, '%FOOD MART%',            NULL,            'Convenience'),
    (116, '%QUIK%',                 NULL,            'Convenience'),
    (117, '%QUICK%',                NULL,            'Convenience'),
    (118, '%KWIK%',                 NULL,            'Convenience'),
    (119, '%XPRESS%',               NULL,            'Convenience'),
    (120, '%MARKET%',               NULL,            'Grocery'),
    (121, '%FOOD%',                 NULL,            'Grocery'),
    (124, '%SAVER%',                NULL,            'Grocery'),
    (125, '%SAVE MORE%',            NULL,            'Grocery'),
    (122, '%GROCERY%',              NULL,            'Grocery'),
    (123, '%SUPERMARKET%',          NULL,            'Grocery'),
    (130, '%MART%',                 NULL,            'Convenience'),
    (131, '% OIL%',                 NULL,            'Convenience'),
    (132, '%GAS%',                  NULL,            'Convenience'),
    (133, '%FUEL%',                 NULL,            'Convenience'),
    (134, '%CONVENIENCE%',          NULL,            'Convenience'),
    (135, '%STOP%',                 NULL,            'Convenience'),
    (136, '%PANTRY%',               NULL,            'Convenience'),
    (137, '%EXPRESS%',              NULL,            'Convenience'),
    (138, '%KONVENIENCE%',          NULL,            'Convenience'),
    (139, '%TWENTY FOUR SEVEN%',    NULL,            'Convenience')
ON CONFLICT (priority) DO NOTHING;
