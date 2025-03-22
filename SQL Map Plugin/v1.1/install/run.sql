DECLARE @b_SqlMapGuid AS UNIQUEIDENTIFIER = '37cd62e9-ee3d-4403-a010-04048f3f2fe8';
DECLARE @BlockId AS INT = (SELECT [ID] FROM [Block] WHERE [Guid] = @b_SqlMapGuid);

DECLARE @i_BlockEntityTypeId AS INT = (SELECT [Id] FROM [EntityType] WHERE [Name]='Rock.Model.Block'); --should be 9
DECLARE @b_DynamicDataBlockTypeId AS INT = (SELECT [Id] FROM [BlockType] WHERE [Guid] = 'e31e02e9-73f6-4b3e-98ba-e0e4f86ca126'); --should be 143

DECLARE @a_ddQueryId AS INT = (SELECT [Id] FROM [Attribute] WHERE [EntityTypeId]=@i_BlockEntityTypeId AND [EntityTypeQualifierColumn]='BlockTypeId' AND [EntityTypeQualifierValue]=@b_DynamicDataBlockTypeId AND [Key]='Query');
DECLARE @a_ddFormattedOutputId AS INT = (SELECT [Id] FROM [Attribute] WHERE [EntityTypeId]=@i_BlockEntityTypeId AND [EntityTypeQualifierColumn]='BlockTypeId' AND [EntityTypeQualifierValue]=@b_DynamicDataBlockTypeId AND [Key]='FormattedOutput');

UPDATE [AttributeValue] SET [Value] = 'SELECT I.name AS IndexName,
    OBJECT_NAME(IC.OBJECT_ID) AS TableName,
    COL_NAME(IC.OBJECT_ID,IC.column_id) AS ColumnName
INTO #tempPKs
FROM sys.indexes AS I 
    INNER JOIN sys.index_columns AS IC ON I.OBJECT_ID = IC.OBJECT_ID AND I.index_id = IC.index_id
WHERE I.is_primary_key = 1

SELECT OBJECT_NAME(F.parent_object_id) AS TableName,
    COL_NAME(FC.parent_object_id,FC.parent_column_id) AS ColumnName,
    OBJECT_NAME(F.referenced_object_id) AS ReferenceTableName,
    COL_NAME(FC.referenced_object_id, FC.referenced_column_id) AS ReferenceColumnName,
    F.name AS ForeignKey
INTO #tempFKs
FROM sys.foreign_keys F
    INNER JOIN sys.foreign_key_columns AS FC ON F.OBJECT_ID = FC.constraint_object_id

SELECT O.name AS TableName,
    C.name AS ColumnName,
    CAST(CASE WHEN EXISTS (SELECT * FROM #tempPKs WHERE TableName = O.name AND ColumnName = C.name) THEN 1 ELSE 0 END AS bit) AS IsPrimaryKey,
    C.is_computed AS IsComputed,
    C.is_identity AS IsIdentity,
    ISNULL(R.TableName + ''.'' + R.ColumnName, '''') AS ReferencedBy,
    ISNULL(RB.ReferenceTableName + ''.'' + RB.ReferenceColumnName, '''') AS [References],
    T.name AS ColType,
    C.max_length AS MaxLength,
    C.is_nullable AS Nullable
    FROM sys.columns C
        INNER JOIN sys.objects O ON C.object_id = O.object_id
        INNER JOIN sys.types T ON C.system_type_id = T.user_type_id
        LEFT JOIN #tempFKs R ON R.ReferenceTableName = O.name AND R.ReferenceColumnName = C.name
        LEFT JOIN #tempFKs RB ON RB.TableName = O.name AND RB.ColumnName = C.name
    WHERE O.is_ms_shipped = 0
    ORDER BY CASE WHEN LEFT(O.name, 1) = ''_'' THEN 4 -- plugin tables
                WHEN O.[type] IN (''IF'',''TF'') THEN 3 -- table functions
                WHEN O.[type] = ''V'' THEN 2 -- views
                ELSE 1 
            END, 
        O.name, C.column_id

DROP TABLE IF EXISTS #tempPKs
DROP TABLE IF EXISTS #tempFKs' WHERE [AttributeId] = @a_ddQueryId AND [EntityId] = @BlockId;
UPDATE [AttributeValue] SET [Value] = '{%- javascript id:''search-db-tables'' %}
    $(document).ready(function()
    {
        //create and add the search box
        var $searchBox = $(''<input id="pageSearch" type="text" class="form-control input-sm" placeholder="Search&hellip;">'')
        $(''#Table-Search'').append($searchBox);
        $searchBox.wrap(''<div class="form-inline mb-2"><div class="form-group"></div></div>'');

        var $target = $(''.search-target''),
            $tableNames = $target.find(''.table-name''),
            $noMatches = $(''<div class="no-matches alert alert-info">No matches found</div>'');

        $noMatches.hide();
        $target.prepend($noMatches);

        $searchBox
            // prevent the enter key from submitting the form
            .on(''keydown'', function(e)
            {
                if (e.keyCode == 13)
                {
                    e.preventDefault();
                    return false;
                }
            })
            // Filter page links when Search box is updated
            .on(''keyup'', function(e)
            {
                var value = $(this).val().toLowerCase();
                    $matched = $tableNames.filter(function()
                    {
                        var $name = $(this),
                            $table = $name.parent(''.db-table''),
                            isShown = $table.is('':visible''),
                            isMatch = $name.text().toLowerCase().indexOf(value) > -1;

                        $table.toggleClass(''match'', isMatch);

                        if (isMatch && !isShown) $table.show();
                        else if (!isMatch && isShown) $table.hide();

                        return isMatch;
                    }),
                    matchCount = $matched.length;

                $noMatches.toggle(matchCount == 0);
            });
    });
{%- endjavascript -%}

<style>
    .table-link { font-size: 75%; }
    .db-table 
    { 
        min-width: 450px; 
        max-width: 33%; 
    }
    .db-table h4 { font-size: 16px; }
    .db-table td, .db-table th { font-size: 12px; }
    .db-table td { word-break: break-word; }
    .col-name { white-space: nowrap; }
    .not-null
    {
        margin-left: 1px;
        font-size: 1.4em;
    }
    .type 
    {
        font-weight: normal;
        font-size: 90%;
        white-space: nowrap;
        opacity: .9;
    }
</style>

{%- capture tablesHTML %}
    <div class="d-flex justify-content-between">
        <div id="Table-Search"></div>
        <figure class="d-inline-block well well-sm">
            <small>
                <i class="fa fa-sm fa-key text-muted"></i> primary key
                <i class="fa fa-sm fa-calculator ml-3 text-muted"></i> computed
                <i class="fa fa-xs fa-plus ml-3 text-info"></i><i class="fa fa-xs fa-plus text-info"></i> identity
                <i class="fa fa-xs fa-asterisk ml-3 text-danger"></i> not null
            </small>
        </figure>
    </div>
    <div class="tables search-target d-flex flex-wrap">

    {%- assign tableName = '''' %}
    {%- assign columnName = '''' %}
    {%- assign rs = '''' %}
    {%- assign rb = '''' %}
    
    {%- for row in rows -%}
        //- start a new row? 
        {%- if columnName != row.ColumnName or tableName != row.TableName -%}
        
            //- end row if not the first item 
            {%- if columnName != '''' %}
                        <td>{{ rb }}</td>
                        <td>{{ rs }}</td>
                    </tr>
            {%- endif -%}
            {%- assign columnName = row.ColumnName %}
            {%- assign rs = '''' %}
            {%- assign rb = '''' -%}

            //- start a new table? 
            {%- if tableName != row.TableName -%}
            
                //- end table if not the first item 
                {%- if tableName != '''' %}
                </table>
            </div>
        </div>
                {%- endif %}
                {%- assign tableName = row.TableName %}
        <div class="db-table mb-4 pr-3 w-25">
            <h4 id="SQLMap.{{ row.TableName }}" class="table-name">{{ row.TableName }} <a href="#SQLMap.{{ row.TableName }}" class="table-link"><i class="fa fa-chain"></i></a></h4>
            <div class="columns d-table w-100">
                <table class=''table table-striped table-condensed w-100''>
                    <tr>
                        <th style="width:20%;">Column</th>
                        <th>Referenced by</th>
                        <th>References</th>
                    </tr>
            {%- endif %}
                    <tr>
                        <th scope="row" class="column">
                            <a id="SQLMap.{{ row.TableName }}.{{ row.ColumnName }}"></a>
                            <span class="col-name">
                                {% if row.IsPrimaryKey == true %}<i class="fa fa-sm fa-key text-muted"></i>{% endif %} {% if row.IsComputed == true %}<i class="fa fa-sm fa-calculator text-muted"></i>{% endif %} {{ row.ColumnName }}{% if row.Nullable == 0 %}<span class="text-danger not-null">*</span>{% endif %}
                            </span>
                            <span class="type text-muted">
                                {{ row.ColType }}({{ row.MaxLength }}) {% if row.IsIdentity == true %}<span class="text-info">++</span>{% endif %}
                            </span>
                        </th>
        {%- endif %}
        {%- if row.References != empty %}{% capture rs %}{{ rs }}<a href="#SQLMap.{{ row.References }}">{{ row.References }}</a><br />{% endcapture %}{% endif %}
        {%- if row.ReferencedBy != empty %}{% capture rb %}{{ rb }}<a href="#SQLMap.{{ row.ReferencedBy }}">{{ row.ReferencedBy }}</a><br />{% endcapture %}{% endif %}
    {%- endfor -%}
                        //- finish off the last row of the last table 
                        <td>{{ rb }}</td>
                        <td>{{ rs }}</td>
                    </tr>
                </table>
            </div>
        </div>
    </div>
{%- endcapture %}

{[ panel title:''Database Tables'' type:''block'' icon:''fa fa-table'' ]}
    {{ tablesHTML }}
{[ endpanel ]}' WHERE [AttributeId] = @a_ddFormattedOutputId AND [EntityId] = @BlockId;