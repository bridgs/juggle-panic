pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

function noop() end

local controllers={1,2}
local catch_fudge=1
local left_wall_x=0
local right_wall_x=128
local ground_y=110

local buttons
local button_presses
local button_releases
local buffered_button_presses

local scene_frame
local entities
local new_entities
local balls

local entity_classes={
	juggler={
		update_priority=1,
		render_layer=2,
		width=18,
		height=11,
		move_x=0,
		left_hand_ball=nil,
		right_hand_ball=nil,
		most_recent_catch_hand=nil,
		anim=nil,
		anim_frames=0,
		sprite_num=0,
		sprite_flipped=false,
		stationary_frames=0,
		wiggle_frames=0,
		throw_cooldown_frames=0,
		init=function(self)
			self:calc_hand_hitboxes()
		end,
		update=function(self)
			local controller=controllers[self.player_num]
			-- move horizontally when left/right buttons are pressed
			self.move_x=ternary(buttons[controller][1],1,0)-
				ternary(buttons[controller][0],1,0)
			local move_speed=1+ternary(self.left_hand_ball,0,1)+ternary(self.right_hand_ball,0,1)
			self.vx=move_speed*self.move_x
			-- don't move if forced to be stationary (during throws/catches)
			if self.stationary_frames>0 then
				self.vx=0
			end
			decrement_counter_prop(self,"stationary_frames")
			self:apply_velocity()
			-- keep the juggler in bounds
			if self.x<self.min_x then
				self.x=self.min_x
				self.vx=max(0,self.vx)
			elseif self.x>self.max_x-self.width then
				self.x=self.max_x-self.width
				self.vx=min(0,self.vx)
			end
			-- debug: spawn balls
			if (button_presses[controller][4] or button_presses[controller][5]) and self.player_num==1 then
				local ball=spawn_entity("ball",self.x,self.y-10,{color=7})
				ball:throw(60,100,40)
			end
			-- throw balls
			decrement_counter_prop(self,"throw_cooldown_frames")
			if (buffered_button_presses[controller][4]>0 or buffered_button_presses[controller][5]>0) and self.throw_cooldown_frames<=0 then
				buffered_button_presses[controller][4]=0
				buffered_button_presses[controller][5]=0
				local preferred_throw_hand=ternary(self.most_recent_catch_hand=="left","right","left")
				if self.move_x<0 then
					preferred_throw_hand="left"
				elseif self.move_x>0 then
					preferred_throw_hand="right"
				end
				if self.left_hand_ball or self.right_hand_ball then
					self.anim="throw"
					self.anim_frames=20
					self.wiggle_frames=0
					self.vx=0
					self.stationary_frames=max(6,self.stationary_frames)
					self.throw_cooldown_frames=4
				end
				-- throw with the left hand unless the right hand is preferred and can throw instead
				if self.left_hand_ball and (preferred_throw_hand=="left" or not self.right_hand_ball) then
					self.sprite_flipped=false
					self:reposition_held_balls()
					self.left_hand_ball:throw(0,80,80)
					self.left_hand_ball=nil
				elseif self.right_hand_ball then
					self.sprite_flipped=true
					self:reposition_held_balls()
					self.right_hand_ball:throw(0,80,80)
					self.right_hand_ball=nil
				end
			end
			-- catch balls
			self:calc_hand_hitboxes()
			local ball
			for ball in all(balls) do
				if not ball.is_held and ball.vy>=0 then
					local is_catching_with_left_hand=(self.left_hand_hitbox and rects_overlapping(self.left_hand_hitbox,ball.hurtbox))
					local is_catching_with_right_hand=(self.right_hand_hitbox and rects_overlapping(self.right_hand_hitbox,ball.hurtbox))
					if is_catching_with_left_hand or is_catching_with_right_hand then
						self.anim="catch"
						self.anim_frames=20
						self.wiggle_frames=0
						self.vx=0
						self.stationary_frames=max(3,self.stationary_frames)
						self.throw_cooldown_frames=ternary(self.left_hand_ball or self.right_hand_ball,0,min(4,self.throw_cooldown_frames))
					end
					-- catch with the left hand if the right can't catch it or if the right is farther from the ball
					if is_catching_with_left_hand and (not is_catching_with_right_hand or ball.x+ball.width/2<self.x+self.width/2) then
						self.left_hand_ball=ball
						self.left_hand_hitbox=nil
						ball:catch()
						self.sprite_flipped=true
						self.most_recent_catch_hand="left"
					-- otherwise catch with the right hand
					elseif is_catching_with_right_hand then
						self.right_hand_ball=ball
						self.right_hand_hitbox=nil
						ball:catch()
						self.sprite_flipped=false
						self.most_recent_catch_hand="right"
					end
				end
			end
			-- calc render data
			if self.anim and self.vx!=0 then
				self.anim_frames=0
				self.anim=nil
				self.sprite_flipped=not self.sprite_flipped
			end
			if decrement_counter_prop(self,"anim_frames") then
				self.anim=nil
				self.sprite_flipped=not self.sprite_flipped
			end
			if self.anim=="catch" then
				self.sprite_num=2
			elseif self.anim=="throw" then
				self.sprite_num=1
			else
				self.sprite_num=0
			end
			if not self.anim then
				increment_counter_prop(self,"wiggle_frames")
				if self.wiggle_frames>ternary(self.move_x==0,20,4) then
					self.sprite_flipped=not self.sprite_flipped
					self.wiggle_frames=0
				end
			end
			-- reposition any held balls
			self:reposition_held_balls()
		end,
		draw=function(self)
			-- self:draw_outline(14)
			-- if self.left_hand_hitbox!=nil then
			-- 	rect(self.left_hand_hitbox.x+0.5,self.left_hand_hitbox.y+0.5,self.left_hand_hitbox.x+self.left_hand_hitbox.width-0.5,self.left_hand_hitbox.y+self.left_hand_hitbox.height-0.5,7)
			-- end
			-- if self.right_hand_hitbox!=nil then
			-- 	rect(self.right_hand_hitbox.x+0.5,self.right_hand_hitbox.y+0.5,self.right_hand_hitbox.x+self.right_hand_hitbox.width-0.5,self.right_hand_hitbox.y+self.right_hand_hitbox.height-0.5,7)
			-- end
			pal(7,0)
			palt(1,true)
			draw_sprite(110,14*self.sprite_num,18,14,self.x,self.y-3,self.sprite_flipped)
			pal()
		end,
		calc_hand_hitboxes=function(self)
			if self.left_hand_ball then
				self.left_hand_hitbox=nil
			else
				self.left_hand_hitbox={
					x=self.x,
					y=self.y+1,
					width=self.width/2,
					height=self.height-1
				}
				if self.vx<0 then
					self.left_hand_hitbox.x+=self.vx
					self.left_hand_hitbox.width-=self.vx
				else
					self.left_hand_hitbox.x-=catch_fudge
					self.left_hand_hitbox.width+=catch_fudge
				end
				if self.right_hand_ball then
					if self.vx>0 then
						self.left_hand_hitbox.width+=self.vx
					else
						self.left_hand_hitbox.width+=catch_fudge
					end
				end
			end
			if self.right_hand_ball then
				self.right_hand_hitbox=nil
			else
				self.right_hand_hitbox={
					x=self.x+self.width/2,
					y=self.y+1,
					width=self.width/2,
					height=self.height-1
				}
				if self.vx>0 then
					self.right_hand_hitbox.width+=self.vx
				else
					self.right_hand_hitbox.width+=catch_fudge
				end
				if self.left_hand_ball then
					if self.vx<0 then
						self.right_hand_hitbox.x+=self.vx
						self.right_hand_hitbox.width-=self.vx
					else
						self.right_hand_hitbox.x-=catch_fudge
						self.right_hand_hitbox.width+=catch_fudge
					end
				end
			end
		end,
		reposition_held_balls=function(self)
			-- calculate hand positions
			local lx,ly,rx,ry
			if self.sprite_num==2 then
				lx,ly,rx,ry=7,2,7,8
			elseif self.sprite_num==1 then
				lx,ly,rx,ry=7,1,7,7
			else
				lx,ly,rx,ry=7,3,7,7
			end
			if self.sprite_flipped then
				lx,ly,rx,ry=rx,ry,lx,ly
			end
			-- move any held balls to those positions
			if self.left_hand_ball then
				self.left_hand_ball.x=self.x+self.width/2-lx-2
				self.left_hand_ball.y=self.y+ly-self.left_hand_ball.height
			end
			if self.right_hand_ball then
				self.right_hand_ball.x=self.x+self.width/2+rx+2-self.right_hand_ball.width
				self.right_hand_ball.y=self.y+ry-self.right_hand_ball.height
			end
		end
	},
	ball={
		update_priority=2,
		render_layer=1,
		width=5,
		height=5,
		gravity=0,
		freeze_frames=0,
		bounce_dir=nil,
		is_held=false,
		color=0,
		add_to_game=function(self)
			add(balls,self)
		end,
		remove_from_game=function(self)
			del(balls,self)
		end,
		init=function(self)
			self:calc_hurtbox()
			self.energy=self.vy*self.vy/2+self.gravity*(ground_y-self.y-self.height)
		end,
		update=function(self)
			if not self.is_held then
				if self.freeze_frames>0 then
					decrement_counter_prop(self,"freeze_frames")
				else
					self.bounce_dir=nil
					self.vy+=self.gravity
					self:apply_velocity()
					self:calc_hurtbox()
					-- bounce off walls
					if self.x<left_wall_x then
						self.x=left_wall_x
						self:calc_hurtbox()
						if self.vx<0 then
							self.vx*=-1
							self.bounce_dir="left"
							self.freeze_frames=1
						end
					elseif self.x>right_wall_x-self.width then
						self.x=right_wall_x-self.width
						self:calc_hurtbox()
						if self.vx>0 then
							self.vx*=-1
							self.bounce_dir="right"
							self.freeze_frames=1
						end
					end
					-- bounce off the ground
					-- if self.y>ground_y-self.height then
					-- 	self.y=ground_y-self.height
					-- 	self:calc_hurtbox()
					-- 	if self.vy>0 then
					-- 		-- we do this so that balls don't lose energy over time
					-- 		self.vy=-sqrt(2*self.energy)
					-- 		self.bounce_dir="down"
					-- 		self.freeze_frames=2
					-- 	end
					-- end
				end
			end
		end,
		post_update=function(self)
			-- balls that hit the ground die
			if not self.is_held and self.y>=ground_y-self.height then
				self:die()
			end
		end,
		draw=function(self)
			-- each ball has a color
			local i
			for i=1,15 do
				pal(i,self.color)
			end
			palt(1,true)
			-- draw the ball squished against the wall/ground
			if self.bounce_dir then
				if self.bounce_dir=="left" or self.bounce_dir=="right" then
					if abs(self.vx)<1 then
						draw_sprite(0,48,5,5,self.x,self.y)
					else
						draw_sprite(ternary(abs(self.vx)>5,40,36),88,4,9,self.x+ternary(self.bounce_dir=="right",1,0),self.y-2,self.bounce_dir=="left")
					end
				elseif self.bounce_dir=="down" then
					if abs(self.vy)<4 then
						draw_sprite(0,48,5,5,self.x,self.y)
					else
						draw_sprite(24,ternary(abs(self.vy)>18,80,76),9,4,self.x-2,self.y+1)
					end
				end
			else
				local speed=sqrt(self.vx*self.vx+self.vy*self.vy)
				-- if it's going slow, just draw an undeformed ball
				if speed<5 then
					draw_sprite(0,48,5,5,self.x,self.y)
				-- otherwise draw a deformed version
				else
					local angle=atan2(self.vx,self.vy)
					local flip_horizontal=(self.vx<0)
					local flip_vertical=(self.vy>0)
					-- figure out which sprite we're going to use
					local sprite_num=flr(24*angle+0.5)
					if flip_vertical then
						sprite_num=24-sprite_num
					end
					if flip_horizontal then
						sprite_num=12-sprite_num
					end
					-- find the right sprite location based on angle
					local sy,sw,sh
					if sprite_num==0 then
						sy,sw,sh=123,16,5
					elseif sprite_num==1 then
						sy,sw,sh=117,15,6
					elseif sprite_num==2 then
						sy,sw,sh=108,13,9
					elseif sprite_num==3 then
						sy,sw,sh=97,11,11
					elseif sprite_num==4 then
						sy,sw,sh=84,9,13
					elseif sprite_num==5 then
						sy,sw,sh=69,6,15
					elseif sprite_num==6 then
						sy,sw,sh=53,5,16
					end
					-- find the right sprite location based on speed
					local sx=mid(0,flr((speed-5)/9),3)*sw
					local x,y=self.x,self.y
					-- handle the other 270 degrees
					if not flip_horizontal then
						x+=self.width-sw
					end
					if flip_vertical then
						y+=self.height-sh
					end
					-- draw the sprite
					draw_sprite(sx,sy,sw,sh,x,y,flip_horizontal,flip_vertical)
				end
			end
		end,
		throw=function(self,distance,height,duration)
			self.is_held=false
			-- let's do some fun math to calculate out the trajectory
			-- duration must be <=180, otherwise overflow will ruin the math
			-- it looks best if duration is an even integer (you get to see the apex)
			local n=(duration+1)*duration/2
			local m=(duration/2+1)*duration/4
			self.vy=n/(m-n/2)
			self.vy*=height/duration
			self.gravity=-self.vy*duration/n
			self.vx=distance/duration
			-- calculate kinetic and potential energy
			self.energy=self.vy*self.vy/2+self.gravity*(ground_y-self.y-self.height)
		end,
		catch=function(self)
			self.is_held=true
			self.freeze_frames=0
			self.vx=0
			self.vy=0
			self.bounce_dir=nil
		end,
		calc_hurtbox=function(self)
			self.hurtbox={
				x=self.x,
				y=self.y,
				width=self.width,
				height=self.height
			}
			if self.vy>0 then
				self.hurtbox.y-=self.vy
				self.hurtbox.height+=self.vy
			elseif self.vy<0 then
				self.hurtbox.height-=self.vy
			end
			if self.vx<0 then
				self.hurtbox.width+=mid(0,-self.vx,2)
			end
			if self.vx>0 then
				self.hurtbox.x-=mid(0,self.vx,2)
				self.hurtbox.width+=mid(0,self.vx,2)
			end
		end
	},
	ball_spawner={}
}

function _init()
	buttons={}
	button_presses={}
	button_releases={}
	buffered_button_presses={}

	scene_frame=0
	entities={}
	new_entities={}
	balls={}
	spawn_entity("juggler",10,ground_y-entity_classes.juggler.height,{
		player_num=1,
		min_x=left_wall_x,
		max_x=64
	})
	spawn_entity("juggler",80,ground_y-entity_classes.juggler.height,{
		player_num=2,
		min_x=64,
		max_x=right_wall_x
	})
	-- add new entities to the game
	add_new_entities()
end

-- local skip_frames=0
function _update()
	-- keep track of inputs (because btnp repeats presses)
	local p
	for p=0,8 do
		if not buttons[p] then
			buttons[p]={}
			button_presses[p]={}
			button_releases[p]={}
			buffered_button_presses[p]={}
		end
		local b
		for b=0,5 do
			button_presses[p][b]=btn(b,2-p) and not buttons[p][b]
			button_releases[p][b]=not btn(b,2-p) and buttons[p][b]
			buttons[p][b]=btn(b,2-p)
			if button_presses[p][b] then
				buffered_button_presses[p][b]=4
			else
				buffered_button_presses[p][b]=decrement_counter(buffered_button_presses[p][b] or 0)
			end
		end
	end
	-- skip_frames+=1
	-- if skip_frames%15>0 then return end
	scene_frame=increment_counter(scene_frame)
	-- sort entities for updating
	sort(entities,function(entity1,entity2)
		return entity1.update_priority>entity2.update_priority
	end)
	-- update each entity
	local entity
	for entity in all(entities) do
		increment_counter_prop(entity,"frames_alive")
		entity:update()
		if decrement_counter_prop(entity,"frames_to_death") then
			entity:die()
		end
	end
	for entity in all(entities) do
		entity:post_update()
	end
	-- add new entities to the game
	add_new_entities()
	-- filter out dead entities
	for entity in all(entities) do
		if not entity.is_alive then
			del(entities,entity)
			entity:remove_from_game()
		end
	end
	-- sort entities for rendering
	sort(entities,function(entity1,entity2)
		return entity1.render_layer>entity2.render_layer
	end)
end

function _draw()
	-- clear the screen
	cls()
	-- draw the sky
	rectfill(left_wall_x,0,right_wall_x-1,127,8)
	pset(left_wall_x,0,0)
	pset(right_wall_x-1,0,0)
	-- draw each entity
	local entity
	foreach(entities,function(entity)
		entity:draw()
		pal()
	end)
	-- draw the ground
	rectfill(0,ground_y,127,127,0)
	pset(left_wall_x,ground_y-1,0)
	pset(right_wall_x-1,ground_y-1,0)
	pset(63,ground_y-1,0)
	pset(64,ground_y-1,0)
end

function spawn_entity(class_name,x,y,args,skip_init)
	local entity
	local the_class=entity_classes[class_name]
	if the_class.extends then
		entity=spawn_entity(the_class.extends,x,y,args,true)
	else
		-- create default entity
		entity={
			is_alive=true,
			frames_alive=0,
			frames_to_death=0,
			update_priority=0,
			render_layer=0,
			x=x or 0,
			y=y or 0,
			vx=0,
			vy=0,
			width=0,
			height=0,
			add_to_game=noop,
			remove_from_game=noop,
			init=noop,
			update=function()
				self:apply_velocity()
			end,
			post_update=noop,
			draw=noop,
			draw_outline=function(self,color)
				rect(self.x+0.5,self.y+0.5,
					self.x+self.width-0.5,self.y+self.height-0.5,color or 8)
			end,
			die=function(self)
				if self.is_alive then
					self:on_death()
					self.is_alive=false
				end
			end,
			on_death=noop,
			apply_velocity=function(self)
				self.x+=self.vx
				self.y+=self.vy
			end
		}
	end
	-- add class properties/methods onto it
	local k,v
	for k,v in pairs(the_class) do
		entity[k]=v
	end
	-- add properties onto it from the arguments
	for k,v in pairs(args or {}) do
		entity[k]=v
	end
	if not skip_init then
		-- initialize it
		entity:init()
		add(new_entities,entity)
	end
	-- return it
	return entity
end

function add_new_entities()
	local entity
	for entity in all(new_entities) do
		add(entities,entity)
		entity:add_to_game()
	end
	new_entities={}
end

-- if condition is true return the second argument, otherwise the third
function ternary(condition,if_true,if_false)
	return condition and if_true or if_false
end

-- increment a counter, wrapping to 20000 if it risks overflowing
function increment_counter(n)
	return n+ternary(n>32000,-12000,1)
end

-- increment_counter on a property of an object
function increment_counter_prop(obj,k)
	obj[k]=increment_counter(obj[k])
end

-- decrement a counter but not below 0
function decrement_counter(n)
	return max(0,n-1)
end

-- decrement_counter on a property of an object, returns true when it reaches 0
function decrement_counter_prop(obj,k)
	if obj[k]>0 then
		obj[k]=decrement_counter(obj[k])
		return obj[k]<=0
	end
end

-- filter out anything in list for which func is false
-- function filter(list,func)
-- 	local item
-- 	for item in all(list) do
-- 		if not func(item) then
-- 			del(list,item)
-- 		end
-- 	end
-- end

-- bubble sorts a list according to a comparison func
function sort(list,func)
	local i
	for i=1,#list do
		local j=i
		while j>1 and func(list[j-1],list[j]) do
			list[j],list[j-1]=list[j-1],list[j]
			j-=1
		end
	end
end

-- check to see if two axis-aligned rectangles are overlapping
function rects_overlapping(x1,y1,w1,h1,x2,y2,w2,h2)
	if type(x2)=="table" then
		x2,y2,w2,h2=x2.x,x2.y,x2.width,x2.height
	elseif type(y1)=="table" then
		x2,y2,w2,h2=y1.x,y1.y,y1.width,y1.height
	end
	if type(x1)=="table" then
		x1,y1,w1,h1=x1.x,x1.y,x1.width,x1.height
	end
	return x1+w1>x2 and x2+w2>x1 and y1+h1>y2 and y2+h2>y1
end

function draw_sprite(sx,sy,sw,sh,x,y,...)
	sspr(sx,sy,sw,sh,x+0.5,y+0.5,sw,sh,...)
end

__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111111111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111111111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111111111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111177771111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111177771111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000711777177771111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000777777777771111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000177717777771111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111177777711111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111117777777777117
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111117777771777777
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111117711771117771
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111777711771111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111777711111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111177111111111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111771111111111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111771111111111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111777177771111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111777177771111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111177777771111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111117777771111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111711777771111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111711177777711111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111777777777777117
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111777777771777777
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111771117771
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111771111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111777711111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111111111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111111111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111111111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111117777111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000711777117777111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000777777717777111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000177717777777111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111777771111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111711177777111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111777777777711111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111777777777777117
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111771777777
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111771117771
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111777711111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1ccc1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ccccc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ccccc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ccccc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1ccc1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1bbb11aaa11199111881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1bbbb1aaa11999118881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbbbbaaaaa1999118881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbbbbaaaaa1999118881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbbbbaaaa11999118881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1bbb1aaaa11999118881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1bb111aaa11999118881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000001aaa11999118881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000001aaa11999118881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000001aa111999118881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000001991118881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000001991118881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000018881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000018881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000018811000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000011811000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
111bb1111aa111199111118100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11bbbb11aaaa11999911188800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11bbbb11aaaa11999911188800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1bbbbb1aaaaa11999111888800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1bbbb11aaaa119999111888100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1bbbb11aaaa119999111888100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11bb11aaaa1119991118881100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000aaaa1199991118881111ccccc1100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000aaa1119991111888111ccccccc100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000009991118881111ccccccc100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000099111188811111ccccc1100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000088811111111111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000008811111cc111cc100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000881111ccccccccc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000001111111ccccccc100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
111111bbb111111aaa11111119911111118800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11111bbbb11111aaaa11111199911111188800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1111bbbbb11111aaaa11111999911111888800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1111bbbb11111aaaa111111999111111888100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1111bbbb11111aaaa1111199991111188881111111c1000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1111bbb11111aaaa111119999111118888111cc11ccc000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000111aaa111111999111111888111cccc1ccc000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000111aa1111119999111118888111cccc11cc000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000119991111118881111cccc11cc000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000119911111188881111cccc11cc000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000188811111cccc1ccc000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000008881111111cc11ccc000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000881111111111111c1000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1111111bbbb11111111aaa1111111199911111111188000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1111111bbbb1111111aaaa1111111999911111118888000000000000000000000000000000000000000000000000000000000000000000000000000000000000
111111bbbbb111111aaaaa1111119999911111188888000000000000000000000000000000000000000000000000000000000000000000000000000000000000
111111bbbb111111aaaaa11111199999111111888881000000000000000000000000000000000000000000000000000000000000000000000000000000000000
111111bbbb11111aaaaa111111999991111118888811000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000001111aaaa1111111999911111118881111000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000001111aa111111119999111111188811111000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000001119911111111888111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000018881111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000088811111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000088111111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1111111111bbb1111111111aaa111111111199911111111118880000000000000000000000000000000000000000000000000000000000000000000000000000
11111111bbbbb11111111aaaaa111111119999911111111888880000000000000000000000000000000000000000000000000000000000000000000000000000
1111111bbbbbb1111111aaaaaa111111199999111111118888810000000000000000000000000000000000000000000000000000000000000000000000000000
1111111bbbbb1111111aaaaaa1111119999991111111888888110000000000000000000000000000000000000000000000000000000000000000000000000000
1111111bbbb1111111aaaaa111111199999111111188888811110000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000011111aaa11111111999991111111888888111110000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000111999111111118888811111110000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000088881111111110000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000088111111111110000000000000000000000000000000000000000000000000000000000000000000000000000
11111111111bbb111111111111aaa111111111111199111111111111888100000000000000000000000000000000000000000000000000000000000000000000
111111111bbbbbb111111111aaaaaa11111111199999911111111188888800000000000000000000000000000000000000000000000000000000000000000000
11111111bbbbbbb1111111aaaaaaaa11111119999999911111188888888100000000000000000000000000000000000000000000000000000000000000000000
11111111bbbbbb1111111aaaaaaaa111111999999999111188888888811100000000000000000000000000000000000000000000000000000000000000000000
111111111bbb111111111aaaaaa11111119999999111118888888811111100000000000000000000000000000000000000000000000000000000000000000000
000000000000000111111aaa11111111119999111111118888811111111100000000000000000000000000000000000000000000000000000000000000000000
11111111111bbb11111111111111aa11111111111111111111111111111111110000000000000000000000000000000000000000000000000000000000000000
1111111111bbbbbb1111111aaaaaaaaa111111999999999911888888888888880000000000000000000000000000000000000000000000000000000000000123
111111111bbbbbbb111111aaaaaaaaaa111199999999999988888888888888880000000000000000000000000000000000000000000000000000000000004567
111111111bbbbbbb111111aaaaaaaaaa1111999999999991188888888888888100000000000000000000000000000000000000000000000000000000000089ab
11111111111bbbb11111111111aaaa1111111111111111111111111111111111000000000000000000000000000000000000000000000000000000000000cdef
