
class ResourceManager extends Class

	@mixin EmitterMixin

	@resourceGuid: 1
	@ajaxDefaults:
		dataType: 'json'
		cache: false

	calendar: null
	topLevelResources: null # if null, indicates not fetched
	resourcesById: null
	fetching: null # a promise. the last fetch. never cleared afterwards


	constructor: (@calendar) ->
		@initializeCache()


	# Resource Data Getting
	# ------------------------------------------------------------------------------------------------------------------


	hasFetched: ->
		@fetching and @fetching.state() == 'resolved'


	getResources: -> # returns a promise
		# never fetched? then fetch... (TODO: decouple from fetching)
		if not @fetching
			getting = $.Deferred()
			syncThen @fetchResources(), ->
				getting.resolve(@topLevelResources)
			, ->
				getting.resolve([])
			getting.promise()
		# otherwise, return what we already have...
		else
			$.Deferred().resolve(@topLevelResources).promise()


	# will always fetch, even if done previously.
	# returns a promise.
	fetchResources: ->
		prevFetching = @fetching
		syncThen prevFetching, =>
			@fetching = $.Deferred()
			@fetchResourceInputs (resourceInputs) =>
				@setResources(resourceInputs, Boolean(prevFetching))
				@fetching.resolve(@topLevelResources)
			@fetching.promise()


	# calls callback when done
	fetchResourceInputs: (callback) ->
		source = @calendar.options['resources']

		if $.type(source) == 'string'
			source = { url: source }

		switch $.type(source)

			when 'function'
				@calendar.pushLoading()
				source (resourceInputs) =>
					@calendar.popLoading()
					callback(resourceInputs)

			when 'object'
				@calendar.pushLoading()
				$.ajax($.extend({}, ResourceManager.ajaxDefaults, source))
					.done (resourceInputs) =>
						@calendar.popLoading()
						callback(resourceInputs)

			when 'array'
				callback(source)

			else
				callback([])


	# fires the 'reset' handler with the already-fetch resource data
	resetResources: ->
		syncThen @getResources(), => # ensures initial fetch happened
			@trigger('reset', @topLevelResources)


	getResourceById: (id) -> # assumes already returned from fetch
		@resourcesById[id]


	getFlatResources: ->
		for id of @resourcesById
			@resourcesById[id]


	# Resource Adding
	# ------------------------------------------------------------------------------------------------------------------


	initializeCache: ->
		@topLevelResources = []
		@resourcesById = {}


	setResources: (resourceInputs, isReset) ->
		@initializeCache()

		resources = for resourceInput in resourceInputs
			@buildResource(resourceInput)

		validResources = (resource for resource in resources \
			when @addResourceToIndex(resource))

		for resource in validResources
			@addResourceToTree(resource)

		if isReset
			@trigger('reset', @topLevelResources)
		else
			@trigger('set', @topLevelResources)

		@calendar.trigger('resourcesSet', null, @topLevelResources)


	addResource: (resourceInput) -> # returns a promise
		syncThen @fetching, =>
			resource = @buildResource(resourceInput)
			if @addResourceToIndex(resource)
				@addResourceToTree(resource)
				@trigger('add', resource)
				resource
			else
				false


	addResourceToIndex: (resource) ->
		if @resourcesById[resource.id]
			false
		else
			@resourcesById[resource.id] = resource
			for child in resource.children
				@addResourceToIndex(child)
			true


	addResourceToTree: (resource) ->
		if not resource.parent
			parentId = String(resource['parentId'] ? '')

			if parentId
				parent = @resourcesById[parentId]
				if parent
					resource.parent = parent
					siblings = parent.children
				else
					return false
			else
				siblings = @topLevelResources

			siblings.push(resource)
		true


	# Resource Removing
	# ------------------------------------------------------------------------------------------------------------------


	removeResource: (idOrResource) ->
		id =
			if typeof idOrResource == 'object'
				idOrResource.id
			else
				idOrResource

		syncThen @fetching, =>
			resource = @removeResourceFromIndex(id)
			if resource
				@removeResourceFromTree(resource)
				@trigger('remove', resource)
			resource


	removeResourceFromIndex: (resourceId) ->
		resource = @resourcesById[resourceId]
		if resource
			delete @resourcesById[resourceId]
			for child in resource.children
				@removeResourceFromIndex(child.id)
			resource
		else
			false


	removeResourceFromTree: (resource, siblings=@topLevelResources) ->
		for sibling, i in siblings
			if sibling == resource
				resource.parent = null
				siblings.splice(i, 1)
				return true
			if @removeResourceFromTree(resource, sibling.children)
				return true
		false


	# Resource Data Utils
	# ------------------------------------------------------------------------------------------------------------------


	buildResource: (resourceInput) ->

		resource = $.extend({}, resourceInput)
		resource.id = String(resourceInput.id ? '_fc' + ResourceManager.resourceGuid++)

		# TODO: consolidate repeat logic
		rawClassName = resourceInput.eventClassName
		resource.eventClassName =
			switch $.type(rawClassName)
				when 'string'
					rawClassName.split(/\s+/)
				when 'array'
					rawClassName
				else
					[]

		resource.children =
			for childInput in resourceInput.children ? []
				child = @buildResource(childInput)
				child.parent = resource
				child

		resource

