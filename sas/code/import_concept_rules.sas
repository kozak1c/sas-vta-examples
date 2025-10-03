/*******************************************
 *
 * Name: import_concept_rules_with_comments_expanded.sas
 *
 * Purpose: import concept rules from a concept node by VTA project name
 *
 * Assumption(s): export_concept_rules_with_comments.sas has been executed
 *
 * Author(s): Bruce Mills
 *
 * Copyright(c) 2025 SAS Institute Inc., Cary, NC, USA. All Rights Reserved.
 *
*******************************************/
/*Table with Concepts*/
%let con_rules=casuser.concept_export;

/*New Empty Concept Node to Import Rules into*/
/*replace xxxxxxxxxxxx with appropriate value*/
%let liti_binary_table_name = "xxxxxxxxxxxx_CONCEPT_BINARY";

cas;
caslib _all_ assign;

%macro vta_concept_create;
%let BASE_URI=%sysfunc(getoption(servicesbaseurl));

/*Create macro varible for the Concept Node's UUID*/
data _null_;
	bin_table=&liti_binary_table_name;
	id=scan(bin_table,1,'_');
	concept_tax_uri=cats("&base_uri","/conceptTaxonomy/taxonomies/",strip(id),"/concepts");
	call symputx("concept_tax_uri",concept_tax_uri);
run;

options compress=yes;
/*Prep the Concepts with Name, Path, Levels*/
data casuser.concepts ;
	set &con_rules;
	name=scan(fullpath,1,":");
	path=scan(fullpath,2,":");
	levels=countc(path,"/")+1;
	obs_id=_n_;
	rename caseInsensitive=case;
run;

/*Create macro variable for Max number of folder levels in Taxonomy*/
proc sql noprint;
	select max(levels) into :lev_cnt
	from casuser.concepts;
quit;

/*Break the Fullpath into variables for each Level of folder structure*/
data casuser.concepts_levels;
	set casuser.concepts;
	length lev_1-lev_%trim(&lev_cnt.) $50.;
	array lev(&lev_cnt) lev_1-lev_%trim(&lev_cnt.);
	do i = 1 to &lev_cnt;
		lev(i) = strip(scan(path,i,"/"));
	end;
	drop i;
run;

/*Collapse rows into single row per rule*/
data casuser.concepts_collapse;
	set casuser.concepts_levels;
	by name rule_line_id;
	length value varchar(*) parentId $50;
	catx_dlm="0a"x;
	retain value;
	value=catx(strip(catx_dlm),value,rule_line);
	if first.name then value=rule_line;
run;

/*Prep data for import*/
data casuser.concepts_dedup;
	set casuser.concepts_collapse;
	length value varchar(*) parentId $50 isHelper caseInsensitive $5;
	by fullpath obs_id;
	if last.fullpath;
	if enabled=1 then isHelper='false'; else isHelper='true';
	if case=1 then 	caseInsensitive = 'true'; else caseInsensitive='false';
run;

/*Loop through all the Folder Levels of the taxonomy*/
%do i = 1 %to &lev_cnt;
	/*Create macro variable for the number of concepts at each level of taxonomy*/
	proc sql noprint;
		select count(*) into :obs_cnt
		from casuser.concepts_dedup
		where levels=&i;
	quit;

	/*Loop through all concepts for a given level*/
	%do j = 1 %to &obs_cnt;

		/*Choose a specific Concept and create macro variable for Name*/
		filename code temp;
		data casuser.concepts_export;
			set casuser.concepts_dedup (where=(levels=&i));
			by fullpath;
			if _n_ = &j;
			call symput("m_name",name);
			keep name value parentID isHelper caseInsensitive;
		run;
		
		/*Export the concept to JSON format*/
		filename json_org temp;
		proc json out=json_org keys nosastags;
			export casuser.concepts_export;
		run;

		/*Clean JSON to fit expected format for VTA API*/
		data casuser.json_fix;
			length raw $32000. full_json varchar(*);
			infile json_org truncover recfm=f lrecl=32000 end=eof;
			input @1 raw $char32000.;
			retain full_json;
			full_json=cats(full_json,raw);
			keep full_json;
			if eof then do;
				full_json=tranwrd(full_json,"[{","{");
				full_json=tranwrd(full_json,"}]","}");
				full_json=tranwrd(full_json,':"false"',':false');
				full_json=tranwrd(full_json,':"true"',':true');
				output;
			end;
		run;

		/*Rewrite cleaned JSON back to JSON format*/
		filename json_fix temp;
		data _null_;
			set casuser.json_fix;
			file json_fix lrecl=999999;
			put full_json @@;
		run;

		filename h_out temp;
		filename out temp;

		/*Add a concept rule to taxonomy*/
		proc http url="&concept_tax_uri"
			method='post'
			oauth_bearer=sas_services
			in=json_fix
			out=out
			headerout= h_out
			CT="application/vnd.sas.text.concept+json";
		run;

		libname con_out json fileref=out;
		/*Find the UUID of the newly added concept*/
		data _null_;
			set con_out.root;
			call symput("parent_id",id);
		run;
	
		/*Update the ParentID for all concepts that are in subfolders of created concept*/
		data casuser.concepts_dedup;
			set casuser.concepts_dedup;
			if levels=sum(&i,1) and lev_&i="&m_name" then parentId="&parent_id";
		run;
	%end;
%end;
%mend;
%vta_concept_create;