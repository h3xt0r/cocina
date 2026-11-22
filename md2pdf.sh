#!/usr/bin/env bash
# Convierte uno o varios archivos Markdown a PDF.
# Usa pandoc para generar HTML y un navegador headless (o wkhtmltopdf) para imprimirlo.
# La hoja de estilo se genera en un directorio temporal; el PDF final es autocontenido.

set -euo pipefail

output_directory="."
custom_css_file=""
page_orientation="portrait"
include_table_of_contents="yes"
pdf_engine=""
temp_directory=""
processed_count=0
input_files=()

usage() {
    cat <<'AYUDA'
Uso: md2pdf.sh [OPCIONES] archivo.md [archivo.md ...]

Opciones:
  -o, --output DIRECTORIO   Directorio de salida (por defecto, el directorio actual).
  -c, --css ARCHIVO         Hoja de estilo CSS propia en lugar de la incluida.
  -l, --landscape           Orientación apaisada (por defecto, vertical).
      --no-toc              No incluir índice.
  -h, --help                Mostrar esta ayuda.

Salida: cada archivo archivo.md genera archivo.pdf en el directorio de salida.

Requisitos: pandoc y chromium, chromium-browser, google-chrome o wkhtmltopdf.
AYUDA
}

check_dependencies() {
    if ! command -v pandoc >/dev/null 2>&1; then
        echo "Error: no se encontró pandoc." >&2
        exit 1
    fi

    if command -v chromium >/dev/null 2>&1; then
        pdf_engine="chromium"
    elif command -v chromium-browser >/dev/null 2>&1; then
        pdf_engine="chromium-browser"
    elif command -v google-chrome >/dev/null 2>&1; then
        pdf_engine="google-chrome"
    elif command -v wkhtmltopdf >/dev/null 2>&1; then
        pdf_engine="wkhtmltopdf"
    else
        echo "Error: se requiere chromium, google-chrome o wkhtmltopdf." >&2
        exit 1
    fi
}

write_default_css() {
    local destination="$1"

    cat > "$destination" <<CSS
@page {
  size: letter $page_orientation;
  margin: 12.7mm;
}

html {
  font-family: "Noto Sans", "DejaVu Sans", sans-serif;
  font-size: 9.5pt;
  color: #1f2933;
}

body {
  margin: 0;
  line-height: 1.35;
}

h1 {
  font-size: 19pt;
  color: #123c69;
  margin: 0 0 6mm 0;
  border-bottom: 2px solid #123c69;
  padding-bottom: 2mm;
}

h2 {
  font-size: 13pt;
  color: #123c69;
  margin: 7mm 0 3mm 0;
  border-bottom: 1px solid #a8b6c4;
  padding-bottom: 1mm;
  page-break-after: avoid;
}

h3 {
  font-size: 10.5pt;
  color: #2c5d87;
  margin: 5mm 0 2mm 0;
  page-break-after: avoid;
}

p { margin: 0 0 2.5mm 0; }

table {
  width: 100%;
  border-collapse: collapse;
  margin: 0 0 4mm 0;
  font-size: 8.6pt;
  page-break-inside: avoid;
}

thead { display: table-header-group; }

th {
  background: #123c69;
  color: #ffffff;
  text-align: left;
  font-weight: 600;
  padding: 1.6mm 2mm;
  border: 0.4pt solid #123c69;
}

td {
  padding: 1.4mm 2mm;
  border: 0.4pt solid #c4ced8;
  vertical-align: top;
}

tbody tr:nth-child(even) { background: #f2f6fa; }

code {
  font-family: "DejaVu Sans Mono", monospace;
  font-size: 8.1pt;
  color: #8b2f2f;
}

strong { color: #123c69; }

blockquote {
  margin: 3mm 0;
  padding: 2mm 3mm;
  border-left: 3px solid #2c5d87;
  background: #eef4f9;
}

hr { border: 0; border-top: 1px solid #a8b6c4; margin: 5mm 0; }

ul { margin: 0 0 2.5mm 0; padding-left: 5mm; }

#TOC { page-break-after: always; }
#TOC ul { list-style: none; padding-left: 4mm; }
#TOC > ul { padding-left: 0; }
CSS
}

convert_to_pdf() {
    local input_file="$1"
    local output_file="$2"
    local html_file="$temp_directory/pagina.html"
    local document_title
    local -a toc_arguments=()

    document_title="$(basename "$input_file")"
    document_title="${document_title%.*}"

    if [ "$include_table_of_contents" = "yes" ]; then
        toc_arguments=(--toc --toc-depth=2)
    fi

    pandoc "$input_file" \
        --from=markdown \
        --to=html5 \
        --standalone \
        "${toc_arguments[@]}" \
        --metadata "title=$document_title" \
        --css "$temp_directory/estilo.css" \
        --output "$html_file"

    case "$pdf_engine" in
        chromium|chromium-browser|google-chrome)
            local engine_log="$temp_directory/chromium.out"
            if ! "$pdf_engine" \
                --headless \
                --no-sandbox \
                --disable-gpu \
                --disable-dev-shm-usage \
                --no-pdf-header-footer \
                --user-data-dir="$temp_directory/perfil-$processed_count" \
                --print-to-pdf="$output_file" \
                "file://$html_file" > "$engine_log" 2>&1; then
                echo "Error: falló la impresión a PDF de: $input_file" >&2
                cat "$engine_log" >&2
                exit 1
            fi
            ;;
        wkhtmltopdf)
            wkhtmltopdf --encoding UTF-8 --quiet "$html_file" "$output_file"
            ;;
    esac
}

main() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -o|--output)
                if [ "$#" -lt 2 ]; then
                    echo "Error: -o requiere un directorio." >&2
                    exit 1
                fi
                output_directory="$2"
                shift 2
                ;;
            -c|--css)
                if [ "$#" -lt 2 ]; then
                    echo "Error: -c requiere un archivo CSS." >&2
                    exit 1
                fi
                custom_css_file="$2"
                shift 2
                ;;
            -l|--landscape)
                page_orientation="landscape"
                shift
                ;;
            --no-toc)
                include_table_of_contents="no"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                while [ "$#" -gt 0 ]; do
                    input_files+=("$1")
                    shift
                done
                ;;
            -*)
                echo "Error: opción desconocida: $1" >&2
                usage >&2
                exit 1
                ;;
            *)
                input_files+=("$1")
                shift
                ;;
        esac
    done

    if [ "${#input_files[@]}" -eq 0 ]; then
        echo "Error: se requiere al menos un archivo .md." >&2
        usage >&2
        exit 1
    fi

    for input_file in "${input_files[@]}"; do
        if [ ! -f "$input_file" ] || [ ! -r "$input_file" ]; then
            echo "Error: no se puede leer el archivo: $input_file" >&2
            exit 1
        fi
    done

    if [ -n "$custom_css_file" ] && { [ ! -f "$custom_css_file" ] || [ ! -r "$custom_css_file" ]; }; then
        echo "Error: no se puede leer la hoja de estilo: $custom_css_file" >&2
        exit 1
    fi

    check_dependencies
    mkdir -p "$output_directory"

    temp_directory="$(mktemp -d "${TMPDIR:-/tmp}/md2pdf.XXXXXX")"
    trap 'rm -rf "$temp_directory"' EXIT

    local css_source="$temp_directory/estilo.css"
    if [ -n "$custom_css_file" ]; then
        cp "$custom_css_file" "$css_source"
    else
        write_default_css "$css_source"
    fi

    for input_file in "${input_files[@]}"; do
        local output_file
        local base_name
        base_name="$(basename "$input_file")"
        base_name="${base_name%.*}"
        output_file="$output_directory/$base_name.pdf"

        convert_to_pdf "$input_file" "$output_file"
        processed_count=$((processed_count + 1))
        echo "Generado: $output_file"
    done

    echo "Total: $processed_count archivo(s) convertido(s)."
}

main "$@"
