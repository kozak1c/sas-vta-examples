/*******************************************
 *
 * Name: export_concept_rules_with_comments.sas
 *
 * Purpose: export concept rules from a concept node by VTA project name
 *
 * Author(s): Bruce Mills
 *
 * Copyright(c) 2025 SAS Institute Inc., Cary, NC, USA. All Rights Reserved.
 *
*******************************************/
cas;
caslib _all_ assign;

options compress=yes;

%let BASE_URI=%sysfunc(getoption(servicesbaseurl));

/* specify VTA project name */
%let model_name = %str(Color_Project);

/*Delete previous Concept Export Table*/
%if %sysfunc(exist(casuser.concept_export)) %then %do;
	proc delete data=casuser.concept_export;
	run;
%end;

/*Get a List of all the VTA model studio projects*/
filename projs temp;
proc http 
	url="&base_uri/analyticsGateway/projects?start=0&limit=9999&filter=in(projectType,%20%27text%27)"
	out=projs
	oauth_bearer=sas_services;
run;

libname projs json;

/*Add filter for specific project of interest*/
data proj_filter;
	set projs.items;
	if name in ("&model_name.");
run;

/*Get the count of the VTA projects to Loop through  */
proc sql noprint;
	select count(*) into: proj_cnt
	from proj_filter;
quit;

/*Loop through all selected projects to extract rules  */
%macro extract_loop;

%do proj_loop_id = 1 %to &proj_cnt;
	/*Defines macro variables for model studio UUID and Name for the project*/
	data _null_;
		set proj_filter;
		if _n_ = &proj_loop_id;
		call symput("proj_id",strip(id));
		call symput("proj_nm",strip(name));
	run;

	/*Get information on a specific VTA project by it's UUID*/
	filename prj_data temp;
	proc http 
		url="&base_uri/analyticsGateway/projects/&proj_id"
		out=prj_data
		oauth_bearer=sas_services;
	run;

	libname prj_data json;

	/*Identify the data souce used by the project*/
	data _null_;
		set prj_data.providerspecificproperties;
		call symput ("prj_data",strip(textAnalyticsOriginalDataUri));
	run;

	/*Get the list of Pipelines in a Model Studio Project*/
	filename pipes temp;
	proc http 
		url="&base_uri/analyticsGateway/projects/&proj_id/pipelines"
		out=pipes
		oauth_bearer=sas_services;
	run;

	libname pipes json;
	
	/*Create a macro variable for the number of pipelines*/
	data _null_;
		set pipes.root;
		call symput("pipe_cnt",count);
	run;

	/*Loop through every Pipeline*/
	%do pipe_loop_id = 1 %to &pipe_cnt;
		
	/*Create macro varibles for the Pipeline UUID and Name*/
		data _null_;
			set pipes.items;
			if _n_ = &pipe_loop_id;
			call symput("pipe_id",strip(id));
			call symput ("pipe_name",strip(name));
		run;
		
		/*Returns details for a specific Pipeline in a Model Studio Project*/
		filename prj_pipe temp;
		proc http 
			url="&base_uri/analyticsGateway/projects/&proj_id/pipelines/&pipe_id"
			out=prj_pipe
			oauth_bearer=sas_services;
		run;

		libname prj_pipe json;

		/*Finds all the Concept Nodes Used in a Pipeline*/
		proc sql;
			create table concept_nodes as
			select b.p3 as id, b.value as name
			from prj_pipe.alldata (where=(value="concepts" and p4="classification")) a 
			left join prj_pipe.alldata(where=(p4='name')) b
				on a.p3 = b.p3;
		quit;

		/*Creates a macro variable for the number of Concept Nodes in a specific Pipeline*/
		proc sql noprint;
			select count(*) into :concept_node_cnt
			from concept_nodes;
		quit;
		
		/*Loops through all the invididual Concept Nodes in a specific Project/Pipeline */
		%do concept_node_loop_id = 1 %to &concept_node_cnt;
			/*Creates macro variables for the Concept Node UUID and Name*/
			data _null_;
				set concept_nodes;
				if _n_ = &concept_node_loop_id;
				call symput("concept_node_id",strip(id));
				call symput("concept_node_name",strip(name));
			run;

			/*Gets details for a specific Concept Node*/
			filename c_url temp;
			proc http 
				url="&base_uri/analyticsGateway/projects/&proj_id/pipelines/&pipe_id/components/&concept_node_id"
				out=c_url
				oauth_bearer=sas_services;
			run;
	
			libname c_url json;
			/*Creates macro variable for the Concept's Taxonomy Url*/
			data _null_;
				set c_url.links;
				if rel='taxonomyUrl';
				call symput("tax_url",strip(href));
			run;

			/*Creates macro variable identifiying if Predefined Concepts were enabled*/
			data _null_;
				set c_url.componentproperties;
				call symput ("predefined",includePredefined);
			run;
	
			/*Returns the Concept Node's Taxonomy Configuration*/
			filename c_tax_c temp;
			proc http 
				url="&base_uri/&tax_url/configuration"
				out=c_tax_c
				oauth_bearer=sas_services;
			run;

			/*Extract list of all Concept UUID and their Name/Path */
			data tax_c;
				infile c_tax_c truncover;
				input raw $5000.;

				retain concept_id;
				if scan(raw,1,":") = "Concept ID" then concept_id=scan(raw,2,":");
				if scan(raw,1,":") = 'FULLPATH' then fullpath = substr(raw,10);
				drop raw;
				if fullpath ne '';
				if fullpath not in ("nlpPerson:nlpPerson","nlpPlace:nlpPlace","nlpOrganization:nlpOrganization","nlpDate:nlpDate",
					"nlpTime:nlpTime","nlpMoney:nlpMoney","nlpNounGroup:nlpNounGroup","nlpPercent:nlpPercent","nlpMeasure:nlpMeasure");
			run;

			/*Creates macro variable for the number of concepts in the taxonomy*/
			proc sql noprint;
				select count(*) into : concept_cnt
				from tax_c;
			quit;

			/*Loops through all individual Concepts in a specific Taxomnomy*/
			%do concept_loop_id = 1 %to &concept_cnt;
				
				/*Creates macro variable for a concepts UUID & Path   */
				data _null_;
					set tax_c;
					if _n_ = &concept_loop_id;
					call symput ("concept_id",strip(concept_id));
					call symput ("fullpath",strip(fullpath));
				run;	
	
				/*Get the details of a speicific concept*/
				filename c_rule temp;
				proc http 
					url="&base_uri/&tax_url/concepts/&concept_id"
					out=c_rule
					oauth_bearer=sas_services;
				run;
		
				libname c_rule json;

				/*Read the concept rule definition into a SAS table*/
				data casuser.c_rule_temp;
					length json $32000. raw varchar(*);
					infile c_rule truncover recfm=f lrecl=32000 end=eof;
					input @1 json $char32000.;
					retain raw;
					raw=cats(raw,json);
					if eof;
				run;
				
				/*Clean Rule output*/
				data casuser.c_rule;
					set casuser.c_rule_temp;
					length rule varchar(*);
					s=index(raw,'"value":') + 9;
					e=index(raw,'"version":')-2;
					if s ne e and s ne 9 then do;
						rule = substr(raw,s,e-s);
						rule = tranwrd(rule,'\"', '"');
						rule = tranwrd(rule,'\\', '\');
					end;
					rule=unicode(rule);
					keep rule;
				run;

				/*Assign metadata details for a rule*/
				data casuser.c_rule_v2;
					length project_name project_data pipeline_name node_name concept_name fullpath varchar(*);
					merge casuser.c_rule 
							c_rule.root (keep=createdby modifiedby caseInsensitive enabled priority name creationTimeStamp modifiedTimeStamp taxonomyid);
					project_name="&proj_nm";
					project_data = "&prj_data";
					pipeline_name="&pipe_name";
					node_name="&concept_node_name";
					include_predefined = &predefined;
					fullpath="&fullpath";
					concept_name = strip(name);
					
					length taxonomy_id created_by modified_by varchar(*);
					created_by=strip(createdby);
					modified_by=strip(modifiedby);
					taxonomy_id=strip(taxonomyid);
					format create_dt modified_dt datetime.;
					create_dt=input(creationTimeStamp,anydtdtm.);
					modified_dt=input(modifiedTimeStamp,anydtdtm.);
					drop name creationTimeStamp modifiedTimeStamp createdby modifiedby taxonomyid;
				run;

				/*Append concept rule to the export set*/
				data casuser.concept_export (append=yes);
					set casuser.c_rule_v2;
				run;
			%end;
		%end;
	%end;
%end;
%mend;
%extract_loop;

/*Split Rules into individual rows*/
data casuser.concepts_expand;
	set casuser.concept_export;
	length rule_line varchar(*);
	rule=tranwrd(rule,'\n','0a'x);
	rule=tranwrd(rule,'\r','0d'x);
	rule_line_cnt=max(countw(rule,'0a0d'x),1);
	do rule_line_id = 1 to rule_line_cnt;
		rule_line=scan(rule,rule_line_id,'0a0d'x);
		if substr(rule_line,1,1)="#" then type="Comment";
		else type="Rule";
		output;
	end;
	drop rule rule_line_cnt;
run;