
hook.Add( "PopulateVehicles", "AddVehicleContentt", function( pnlContent, tree, browseNode )

	local Categorised = {}

	-- Grouped by each entry's OWN Category field (workshop vehicle packs
	-- set this themselves, e.g. "Simple Cars", "Half-Life 2") rather than
	-- dumped into one flat "Vehicles" node - that was hiding which pack
	-- everything came from, reported as vehicles "not categorized into
	-- their workshops or anything like they should be".
	local TranslateNames = {
		[ "Chairs" ] = "#spawnmenu.category.chairs",
		[ "Other" ] = "#spawnmenu.category.other",
	}

	local Vehicles = list.Get( "Vehicles" )
	if ( Vehicles ) then
		for k, v in pairs( Vehicles ) do
			local Category = TranslateNames[ v.Category ] or v.Category or "#spawnmenu.category.other"
			if ( !isstring( Category ) ) then Category = tostring( Category ) end
			Categorised[ Category ] = Categorised[ Category ] or {}

			local entry = table.Copy( v )
			entry.SpawnName = k
			table.insert( Categorised[ Category ], entry )
		end
	end

	-- Glide vehicles may register under their own list as well
	local GlideVehicles = list.Get( "glide_vehicles" )
	if ( GlideVehicles ) then
		local Category = "Glide Vehicles"
		Categorised[ Category ] = Categorised[ Category ] or {}

		for k, v in pairs( GlideVehicles ) do
			local entry = table.Copy( v )
			entry.SpawnName = k
			table.insert( Categorised[ Category ], entry )
		end
	end

	local CustomIcons = list.Get( "ContentCategoryIcons" )
	for CategoryName, v in SortedPairs( Categorised ) do

		local node = tree:AddNode( CategoryName, CustomIcons[ CategoryName ] or "icon16/car.png" )

		node.DoPopulate = function( self )

			if ( self.PropPanel ) then return end

			self.PropPanel = vgui.Create( "ContentContainer", pnlContent )
			self.PropPanel:SetVisible( false )
			self.PropPanel:SetTriggerSpawnlistChange( false )

			for k, ent in SortedPairsByMemberValue( v, "PrintName" ) do

				spawnmenu.CreateContentIcon( "vehicle", self.PropPanel, {
					nicename	= ent.PrintName or ent.Name or ent.SpawnName,
					spawnname	= ent.SpawnName,
					material	= ent.IconOverride or ( "entities/" .. ent.SpawnName .. ".png" ),
					admin		= ent.AdminOnly
				} )

			end

		end

		node.DoClick = function( self )

			self:DoPopulate()
			pnlContent:SwitchPanel( self.PropPanel )

		end

	end

	local FirstNode = tree:Root():GetChildNode( 0 )
	if ( IsValid( FirstNode ) ) then
		FirstNode:InternalDoClick()
	end

end )

spawnmenu.AddCreationTab( "#spawnmenu.category.vehicles", function()

	local ctrl = vgui.Create( "SpawnmenuContentPanel" )
	ctrl:EnableSearch( "vehicles", "PopulateVehicles" )
	ctrl:CallPopulateHook( "PopulateVehicles" )

	return ctrl

end, "icon16/car.png", 30 )
