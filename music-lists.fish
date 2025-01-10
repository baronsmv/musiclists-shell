#!/usr/bin/env fish

argparse 'a/aoty=?' 'p/progarchives=?' 'classical' \
's/similarities=?' 'w/wanting' 'e/existing' \
'g/getdirs' \
'copy' 'from=' 'to=' \
'c/compress' \
'v/verbose' 'h/help' \
-- $argv; or return

if set -q _flag_help
	echo \
"Modo de empleo: music-lists [OPCIÓN]...
Descarga listas de música, compara con álbumes obtenidos y los mueve.

  -a, --aoty=[PUNTUACIÓN]          Descarga la lista de AOTY.com.
  -p, --progarchives=[PUNTUACIÓN]  Descarga la lista de Progarchives.com.
  --classical                      Descarga la lista de Classical.net.

  -w, --wanting                    Genera una lista de los álbumes faltantes.
  -e, --existing                   Genera una lista de los álbumes sobrantes.

  -s, --similarities=[RADIO]       Analiza similitudes entre las listas
                                   generadas.

  --copy                           Copia los álbumes que se encuentren en la
                                   lista wanting.
  -g, --getdirs                    Genera una lista con los álbumes en un
                                   directorio.
  --from=DIRECTORIO                Especifica dónde se localizan los álbumes.
  --to=DIRECTORIO                  Especifica hacia dónde se guardan los
                                   álbumes.

  -c, --compress                   Comprime las listas YAML.

  -v, --verbose

  -h, --help  Imprime este mensaje y sale del programa."
	return
end

if [ ! (which lynx) ]; echo "lynx no instalado. Saliendo..."; return; end
if [ ! (which yq) ]; echo "yq no instalado. Saliendo..."; return; end

if set -q _flag_aoty && [ ! "$_flag_aoty" ]; set _flag_aoty 83; end
if set -q _flag_progarchives && [ ! "$_flag_progarchives" ]
	set _flag_progarchives 80
end
if set -q _flag_similarities && [ ! "$_flag_similarities" ]
	set _flag_similarities 0.6
end

set listdir "$HOME/Sync/Scripts/Música/lists/"(date "+%Y-%m")
if [ ! -d "$listdir" ]; mkdir -p "$listdir"; end

set yaml_aoty "$listdir/aoty.yaml"
set yaml_prog "$listdir/prog.yaml"
set yaml_classical "$listdir/classical.yaml"
set yaml_all "$listdir/all.yaml"
set yaml_dirs "$listdir/dirs.yaml"
set yaml_existing "$listdir/existing.yaml"
set yaml_wanting "$listdir/wanting.yaml"
set yaml_tocopy "$listdir/tocopy.yaml"

set compressed "$listdir/yaml.7z"

set equivdir "$HOME/Sync/Scripts/Música/lists/equiv"

set exceptions "$equivdir/exceptions.txt"

function getid \
-d "Regresa un ID con los parametros dados, que pretende ser único y
representativo de un álbum."
	echo (for s in $argv
		echo "$s" \
		| sed 's/[Tt]he //' \
		| sed 's/ EP//' \
		| sed 's/.*: //' \
		| iconv -f UTF-8 -t ASCII//TRANSLIT \
		| sed 's/[^[:alnum:]]\+//g' \
		| cut -c1-14 \
		| tr "[:upper:]" "[:lower:]"
	end) | tr -d ' '
end
function dumpAOTY -a page
	lynx -dump -nolist -width=1000 \
	"$page" \
	| grep -A 8 "[0-9]\. " \
	| sed '/^[[:space:]]*$/d' \
	| grep -Fxv "   USER SCORE" \
	| grep -Fxv "   Amazon" \
	| grep -Fxv "   Spotify" \
	| grep -Fxv "   Music" \
	| tr '\n' '\t' \
	| sed 's/--\t/\n/g' \
	| sed 's/\. /\t/' \
	| sed 's/ - /\t/'
end
function getAOTY -a lowerlimit page
	set n 1
	while true
		for album in (dumpAOTY "$page/$n/")
			set album (echo "$album" | tr '\t' '\n')
			set position $album[1]
			set artist (echo "$album[2]" | trim | sed 's/"/\\\\"/g')
			set title (echo "$album[3]" | trim | sed 's/"/\\\\"/g')
			set year (echo "$album[5]" | rev | cut -d ' ' -f 1 | rev)
			set genre (echo "$album[6]" | trim \
			| sed 's/, /\n/g' | sed '/^[[:space:]]*$/d')
			if [ "$genre" -gt 0 ] 2> /dev/null
				set genre Unknown
				set score (echo "$album[6]" | trim)
				set reviews (echo "$album[7]" \
				| sed 's/[a-zA-Z, ]//g')
			else
				set score (echo "$album[7]" | trim)
				set reviews (echo "$album[8]" \
				| sed 's/[a-zA-Z, ]//g')[1]
			end
			set id (getid "$artist" "$year" "$title")
			if [ "$score" -lt "$lowerlimit" ]; return; end
			echo "$id:"
			echo "  artist: \"$artist\""
			if [ (count $genre) -gt 1 ]
				echo "  genre:"
				for g in $genre
					echo "    - $g"
				end
			else
				echo "  genre: $genre"
			end
			echo "  score: $score"
			echo "  reviews: $reviews"
			echo "  title: \"$title\""
			echo "  year: $year"
			# echo $position >> $HOME/pos.txt
		end
		set n (math "$n + 1")
	end
end
function aotylist -a lowerlimit file \
-d "Regresa una lista YAML con los álbumes mejor valorados por usuarios de
AOTY, con un límite inferior como parámetro."
	echo "---" > "$file"
	for type in lp ep mixtape compilation live soundtrack
		getAOTY $lowerlimit \
		"https://www.albumoftheyear.org/ratings/user-highest-rated/$type/all/" \
		>> "$file"
	end
	# yq 'unique' "$file"
end
function proglist -a lowerlimit \
-d "Regresa una lista YAML con los álbumes mejor valorados por usuarios de
Progarchives, con un límite inferior como parámetro."
	echo "---"
	for n in (
	lynx -dump -listonly "https://www.progarchives.com/" \
	| grep -F "https://www.progarchives.com/subgenre.asp?style=" \
	| rev | cut -d '=' -f 1 | rev | sort -n)
		set genre (
		lynx -dump -nolist "https://www.progarchives.com/subgenre.asp?style=$n" \
		| grep -F "Top Albums" \
		| sed 's/ Top Albums//')
		for album in (
		lynx -dump -nolist -width=1000 \
		"https://www.progarchives.com/top-prog-albums.asp?ssubgenres=$n&salbumtypes=1&smaxresults=250#list" \
		| grep -F "QWR = " -B 1 -A 3 \
		| tr '\n' '\t' \
		| sed 's/--\t/\n/g')
			set album (echo "$album" | tr '\t' '\n')
			set artist (echo "$album[4]" \
			| sed "s| $genre||" | trim | sed 's/"/\\\\"/g')
			set title (echo "$album[3]" | trim | sed 's/"/\\\\"/g')
			set year (echo "$album[5]" | sed 's/[a-zA-Z,= ]//g')
			set score (echo "$album[2]" | sed 's/[a-zA-Z,= ]//g')
			set score (math "ceil $score * 20")
			set gscore (echo "$album[2]" | cut -d '|' -f 1 | trim)
			set reviews (echo "$album[1]" \
			| cut -d '|' -f 2 \
			| sed 's/[a-zA-Z, ]//g')
			set id (getid "$artist" "$year" "$title")
			if [ "$score" -lt "$lowerlimit" ]; continue; end
			echo "$id:"
			echo "  artist: \"$artist\"" | sed 's/"   /"/'
			echo "  genre: $genre"
			echo "  score: $score"
			echo "  reviews: $reviews"
			echo "  title: \"$title\"" | sed 's/"   /"/'
			echo "  year: $year"
		end
	end
end
function classicallist \
-d ""
	for p in (
	lynx -dump -listonly "http://www.classical.net/music/rep/" \
	| grep -F "http://www.classical.net/music/rep/lists/" \
	| rev | cut -d ' ' -f 1 | rev)
		set period (
		lynx -dump -nolist "$p" \
		| grep -Fx "Basic Repertoire" -A 2 | tail -n 1 | xargs)
		for c in (
		lynx -dump -listonly "$p" \
		| grep -F "http://www.classical.net/music/comp.lst/" \
		| rev | cut -d ' ' -f 1 | rev)
			set composer (
			lynx -dump -nolist "$c" \
			| grep "([0-9].*[0-9])" -B 2 | head -n 1 | xargs)
			for opus in (lynx -dump -nolist -width=1000 "$c" \
			| grep -F "Core Repertoire - Start Here!" \
			| sed 's/^Core Repertoire - Start Here!//g' \
			| sed 's/Core Repertoire - Start Here!/Highlight:/g' \
			| sed -z 's/\n    / /g' | sed 's/^ //g' | sed 's/ , /, /g')
				set title
			end
		end
	end
end
function mergelists \
-d "Une las listas y devuelve el resultado ordenado."
	yq eval-all \
	'. as $item ireduce ({}; . * $item)' \
	"$yaml_aoty" \
	"$yaml_prog" \
	| yq 'sort_keys(..)'
end
function retrieve -a yaml \
-d "Imprime la lista en la forma Artista - Álbum (Año)."
	if [ ! -f "$yaml" ]; return; end
	if [ (echo "$yaml" | grep -ix ".*.yaml") ]
		for id in (cat "$yaml" | grep "^[a-zA-Z0-9]" | tr -d ":" | sort)
			set artist (yq .$id.artist "$yaml" | sed 's|/|_|g')
			set title (yq .$id.title "$yaml" | sed 's|/|_|g')
			set year (yq .$id.year "$yaml")
			echo "$artist/$title ($year)"
		end
	else
		cat "$yaml"
	end
end
function asText -a yaml
	echo (dirname "$yaml")/.(basename "$yaml" .yaml).txt
end
function retrieveAsText -a yaml \
-d "Imprime la lista en la forma Artista - Álbum (Año)."
	if [ ! -e "$yaml" ]
		echo "No existe el archivo $yaml Omitiendo..."
		return
	end
	retrieve "$yaml" > (asText "$yaml")
end
function dirtoyaml -a dir
	set artist (dirname "$dir")
	set title (basename "$dir" \
	| rev | cut -d '(' -f 2- | rev | trim)
	set year (basename "$dir" \
	| rev | cut -d '(' -f 1 | rev | sed 's/[() ]//g')
	set id (getid "$artist" "$year" "$title")
	echo "$id:"
	echo "  artist: \"$artist\""
	echo "  title: \"$title\""
	echo "  year: $year"
end
function dirtoid -a dir
	set artist (dirname "$dir")
	set title (basename "$dir" \
	| rev | cut -d '(' -f 2- | rev | trim)
	set year (basename "$dir" \
	| rev | cut -d '(' -f 1 | rev | sed 's/[() ]//g')
	getid "$artist" "$year" "$title"
end
function dedupEntries -a text1 text2 prob
	if [ ! (which ipython3) ]
		echo "ipython3 no instalado. Saliendo..."
		return
	end
	if [ ! "$prob" ]; set prob 0.6; end
	set equiv "$equivdir/"(
	basename "$text1" | rev | cut -d '.' -f 2- | rev)-(
	basename "$text2" | rev | cut -d '.' -f 2- | rev).yaml
	cd (dirname "$text1")
	if [ (echo "$text1" | grep -ix ".*.yaml") ]
		retrieveAsText "$text1"; set text1 (asText "$text1")
		retrieveAsText "$text2"; set text2 (asText "$text2")
	end
	ipython3 -c \
"import sys
from difflib import SequenceMatcher
temp = open(r'.temp.txt', 'a')
for text1 in open(r'"(basename "$text1")"', 'r'):
	for text2 in open(r'"(basename "$text2")"', 'r'):
		if $prob <= SequenceMatcher(None, text1, text2).ratio() < 1 :
			temp.write(str(text1 + text2 + '\n'))
temp.close()"
	echo "Verifique el archivo "./temp" y elimine los duplicados no válidos.
	Al terminar, presione Enter."
	read
	for match in (cat ./.temp.txt | sed -z 's/)\n/)|/g' | sed 's/|$//g')
		set match (echo "$match" | tr '|' '\n')
		echo \"(
		echo $match[1] | sed 's/"/\\\\"/g')\": \"(
		echo $match[2] | sed 's/"/\\\\"/g')\" >> "$equiv"
		grep -Fxv "$match[1]" "$text1" > ./t; mv -f ./t "$text1"
		if [ -e "$y1" ]
			yq -i "del(."(dirtoid "$match[1]")")" "$y1"
		end
	end
	if [ -e "$equiv" ]; sort -u "$equiv" -o "$equiv"; end
	rm ./.temp.txt
end
function getDirs -a parent \
-d "Devuelve los subdirectorios dentro de 'parent', asumiendo que tienen un
formato Artista/Álbum (Año), como entradas YAML."
	if [ ! -d "$parent" ]; return; end
	for dir in (
	find "$parent" -mindepth 2 -maxdepth 2 -type d \
	-not -wholename "*/_CLASSICAL/*" \
	| sort | sed "s|$parent||" | sed -r 's|^/{1,}||')
		dirtoyaml "$dir"
	end
end
function uniqueEntries -a yaml1 yaml2 \
-d "Compara las entradas de dos archivos YAML, y devuelve las que existen en
el primero pero no en el segundo."
	if [ ! -f "$yaml1" -o ! -f "$yaml2" ]; return; end
	for id in (grep "^[a-zA-Z0-9]" "$yaml1" | tr -d ":")
		if [ ! (grep -Fx "$id:" "$yaml2")[1] ]
			set artist (yq .$id.artist "$yaml1")
			set title (yq .$id.title "$yaml1")
			set year (yq .$id.year "$yaml1")
			echo "$id:"
			echo "  artist: \""(echo "$artist" | sed 's/"/\\\\"/g')\"
			echo "  title: \""(echo "$title" | sed 's/"/\\\\"/g')\"
			echo "  year: $year"
		end
	end
end
function removeEquiv -a yaml1 yaml2
	set equiv "$equivdir/"(
	basename "$yaml1" | rev | cut -d '.' -f 2- | rev)-(
	basename "$yaml2" | rev | cut -d '.' -f 2- | rev).yaml
	if set -q _flag_verbose
		echo "Removiendo equivalencias desde el archivo $equiv"
	end
	set text (asText "$yaml1")
	if [ ! -f "$equiv" ]; echo "No existe el archivo $equiv"; return; end
	for key1 in (yq '. | keys[]' "$equiv" | sed 's/"/\\\\"/g')
		for key2 in (grep -F "\"$key1\": \"" "$equiv" | sed "s|.*\": \"||" \
		| sed 's/"$//')
			if [ (grep -Fx (dirtoid "$key2")':' "$yaml2")[1] ]
				if set -q _flag_verbose
					echo "Equivalencia encontrada:"
					echo "  $key1 : $key2"
				end
				yq -i "del(."(dirtoid "$key1")")" "$yaml1"
				if [ -f "$text" ]
					grep -Fxv "$key1" "$text" > ./t; mv -f ./t "$text"
				end
			else if set -q _flag_verbose
				echo "Equivalencia NO encontrada:"
				echo "  $key1 : $key2"
			end
		end
	end
end
function invertEquiv -a yaml
	if [ ! -f "$yaml" ]; return; end
	for key1 in (yq '. | keys[]' "$yaml")
		set key2 (grep -F "\"$key1\":" "$yaml" | sed 's/.*\": \"//' | sed 's/\"$//')
		for k2 in $key2
			echo "\"$k2\": \"$key1\""
		end
	end
end
function copyWanting -a dirfrom dirto
	if not [ -e "$yaml_dirs" -a -e $yaml_existing ]
		echo "No existen los archivos necesarios para copiar."
		return
	end
	if set -q _flag_verbose
		echo "Registrando los álbumes a copiar en $yaml_tocopy"
	end
	# uniqueEntries "$yaml_dirs" "$yaml_existing" > "$yaml_tocopy"
	# retrieveAsText "$yaml_tocopy"
	if not [ -d "$dirfrom" ]
		echo "No existe el directorio de origen $dirfrom"
		return
	end
	for dir in (cat (asText "$yaml_tocopy")) (cat "$exceptions")
		if [ ! -d "$dirfrom/$dir" ]
			echo "No existe el directorio de $dir. Saliendo..."
			return
		end
		if [ ! -d "$dirto/"(dirname "$dirto") ]
			mkdir -p "$dirto/"(dirname "$dir")
		end
		if set -q _flag_verbose
			echo "Copiando el álbum $dir"
		end
		cp -ru "$dirfrom/$dir" "$dirto/$dir"
	end
end
function refreshEquiv
	cat "$equivdir/wanting-dirs.yaml" >> "$equivdir/wanting-existing.yaml"
	cat "$equivdir/existing-all.yaml" >> "$equivdir/existing-wanting.yaml"
	invertEquiv "$equivdir/existing-wanting.yaml" >> "$equivdir/wanting-existing.yaml"
	sort -u "$equivdir/wanting-existing.yaml" -o "$equivdir/wanting-existing.yaml"
	invertEquiv "$equivdir/wanting-existing.yaml" >> "$equivdir/existing-wanting.yaml"
	sort -u "$equivdir/existing-wanting.yaml" -o "$equivdir/existing-wanting.yaml"
	cp -f "$equivdir/wanting-existing.yaml" "$equivdir/wanting-dirs.yaml"
	cp -f "$equivdir/existing-wanting.yaml" "$equivdir/existing-all.yaml"
end

refreshEquiv

if set -q _flag_getdirs
	if not set -q _flag_from
		echo \
		"Se debe especificar la ruta de from para registrar los directorios."
		return
	end
	if [ ! -d $_flag_from ]
		echo "No existe el directorio $_flag_from"
		return
	end
	if set -q _flag_verbose; echo "Registrando los álbumes existentes."; end
	getDirs "$_flag_from" > "$yaml_dirs"
end

if set -q _flag_aoty
	if set -q _flag_verbose
		echo "Descargando la lista de AOTY con la puntuación $_flag_aoty."
	end
	aotylist $_flag_aoty "$yaml_aoty"
end
if set -q _flag_progarchives
	if set -q _flag_verbose
		echo "Descargando la lista de Progarchives con la puntuación" \
		"$_flag_progarchives."
	end
	proglist $_flag_progarchives > "$yaml_prog"
end
if set -q _flag_classical
	if set -q _flag_verbose; echo "Descargando la lista de Classical.Net."; end
	classicallist > "$yaml_classical"
end

if set -q _flag_aoty || set -q _flag_progarchives
	removeEquiv "$yaml_aoty" "$yaml_prog"
	if set -q _flag_similarities
		dedupEntries "$yaml_aoty" "$yaml_prog" "$_flag_similarities"
	end
	mergelists > "$yaml_all"
	retrieveAsText "$yaml_all"
end

if set -q _flag_existing && [ -e "$yaml_dirs" ]
	if [ ! -e "$yaml_all" ]; mergelists > "$yaml_all"; end
	uniqueEntries "$yaml_dirs" "$yaml_all" > "$yaml_existing"
	if set -q _flag_similarities && [ -e "$yaml_wanting" ]
		dedupEntries "$yaml_existing" "$yaml_wanting" "$_flag_similarities"
		refreshEquiv
	end
	removeEquiv "$yaml_existing" "$yaml_all"
	retrieveAsText "$yaml_existing"
end
if set -q _flag_wanting && [ -e "$yaml_dirs" ]
	if [ ! -e "$yaml_all" ]; mergelists > "$yaml_all"; end
	uniqueEntries "$yaml_all" "$yaml_dirs" > "$yaml_wanting"
	if set -q _flag_similarities && [ -e "$yaml_existing" ]
		dedupEntries "$yaml_wanting" "$yaml_existing" "$_flag_similarities"
		refreshEquiv
	end
	removeEquiv "$yaml_wanting" "$yaml_dirs"
	retrieveAsText "$yaml_wanting"
end

if set -q _flag_copy
	if not set -q _flag_from || not set -q _flag_to
		echo "Se requiere especificar las rutas de from y to."
	end
	copyWanting "$_flag_from" "$_flag_to"
end

if set -q _flag_compress
	7z a "$compressed" (find "$listdir" -type f -iname "*.yaml")
	and rm (find "$listdir" -type f -iname "*.yaml")
end

refreshEquiv
