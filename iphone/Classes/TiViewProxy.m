/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2010 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "TiViewProxy.h"
#import "LayoutConstraint.h"
#import "TiView.h"
#import "TitaniumApp.h"
#import "TiBlob.h"
#import <QuartzCore/QuartzCore.h>


@implementation TiViewProxy

@synthesize children;

#pragma mark Internal

-(void)dealloc
{
	RELEASE_TO_NIL(view);
	RELEASE_TO_NIL(children);
	[super dealloc];
}

#pragma mark Subclass Callbacks 

-(void)childAdded:(id)child
{
}

-(void)childRemoved:(id)child
{
}

#pragma mark Public

-(void)add:(id)arg
{
	ENSURE_UI_THREAD(add,arg); 
	ENSURE_ARG_COUNT(arg,1);
	ENSURE_SINGLE_ARG(arg,TiProxy);
	if (children==nil)
	{
		children = [[NSMutableArray alloc] init];
	}
	[children addObject:arg];
	[self layoutChild:arg bounds:view.bounds]; 
	[self childAdded:arg];
}


-(void)remove:(id)arg
{
	ENSURE_UI_THREAD(remove,arg);
	ENSURE_ARG_COUNT(arg,1);
	ENSURE_SINGLE_ARG(arg,TiProxy);
	if (children!=nil)
	{
		[self childRemoved:arg];
		[children removeObject:arg];
		
		if ([children count]==0)
		{
			RELEASE_TO_NIL(children);
		}
	}
	if (view!=nil)
	{
		//TODO: this is temporarily backwards compat with old TiView until everything is ported
		if ([arg isKindOfClass:[TiViewProxy class]])
		{
			UIView *childView = [arg view];
			[childView removeFromSuperview];
		}
		else 
		{
			[(TiView*)arg _destroy];
		}
	}
}

-(void)show:(id)arg
{
	//TODO: animate
	[self setValue:[NSNumber numberWithBool:YES] forKey:@"visible"];
}
 
-(void)hide:(id)arg
{
	//TODO: animate
	[self setValue:[NSNumber numberWithBool:NO] forKey:@"visible"];
}

-(void)animate:(id)arg
{
	ENSURE_UI_THREAD(animate,arg);
	[[self view] animate:arg];
}

-(void)addImageToBlob:(TiBlob*)blob
{
	UIView *myview = [self view];
	UIGraphicsBeginImageContext(myview.bounds.size);
	[myview.layer renderInContext:UIGraphicsGetCurrentContext()];
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	[blob setImage:image];
	UIGraphicsEndImageContext();
}

-(TiBlob*)toImage:(id)args
{
	TiBlob *blob = [[[TiBlob alloc] init] autorelease];
	// we spin on the UI thread and have him convert and then add back to the blob
	[self performSelectorOnMainThread:@selector(addImageToBlob:) withObject:blob waitUntilDone:NO];
	return blob;
}

#pragma mark View

-(void)animationCompleted:(TiAnimation*)animation
{
	[[self view] animationCompleted];
}

-(TiUIView*)newView
{
	NSString * proxyName = NSStringFromClass([self class]);
	if ([proxyName hasSuffix:@"Proxy"]) 
	{
		Class viewClass = nil;
		NSString * className = [proxyName substringToIndex:[proxyName length]-5];
		viewClass = NSClassFromString(className);
		if (viewClass != nil)
		{
			return [[viewClass alloc] init];
		}
	}

	return [[TiUIView alloc] initWithFrame:[self appFrame]];
}

-(BOOL)viewAttached
{
	return view!=nil;
}

-(void)detachView
{
	if (view!=nil)
	{
		[self viewWillDetach];
		[view removeFromSuperview];
		[self viewDidDetach];
		self.modelDelegate = nil;
		RELEASE_TO_NIL(view);
	}
}

-(void)windowDidClose
{
	for (TiViewProxy *child in children)
	{
		[child windowDidClose];
	}
}

-(void)windowWillClose
{
	for (TiViewProxy *child in children)
	{
		[child windowWillClose];
	}
	[self detachView];
}

-(void)viewWillAttach
{
	// for subclasses
}

-(void)viewDidAttach
{
	// for subclasses
}

-(void)viewWillDetach
{
	// for subclasses
}

-(void)viewDidDetach
{
	// for subclasses
}

-(void)willFirePropertyChanges
{
	// for subclasses
	if ([view respondsToSelector:@selector(willFirePropertyChanges)])
	{
		[view performSelector:@selector(willFirePropertyChanges)];
	}
}

-(void)didFirePropertyChanges
{
	// for subclasses
	if ([view respondsToSelector:@selector(didFirePropertyChanges)])
	{
		[view performSelector:@selector(didFirePropertyChanges)];
	}
}

-(BOOL)viewReady
{
	return view!=nil && 
			CGRectIsEmpty(view.bounds)==NO && 
			CGRectIsNull(view.bounds)==NO &&
			[view superview] != nil;
}

-(void)firePropertyChanges
{
	[self willFirePropertyChanges];
	
	id<NSFastEnumeration> values = [self validKeys];
	if (values == nil)
	{
		values = [dynprops allKeys];
	}
	
	[view readProxyValuesWithKeys:values];

	[self didFirePropertyChanges];
}

-(TiUIView*)view
{
	if (view == nil)
	{
		[self viewWillAttach];
		
		// on open we need to create a new view
		view = [self newView];
		view.proxy = self;
		view.parent = self;
		view.layer.transform = CATransform3DIdentity;
		view.transform = CGAffineTransformIdentity;
		
		// fire property changes for all properties to our delegate
		[self firePropertyChanges];
		
		for (id child in self.children)
		{
			//TODO: temporary cast until we port fully
			if ([child isKindOfClass:[TiViewProxy class]])
			{
				TiUIView *childView = [(TiViewProxy*)child view];
				[childView setParent:self];
			}
		}
		
		[self viewDidAttach];

		// make sure we do a layout of ourselves
		LayoutConstraint layout;
		ReadConstraintFromDictionary(&layout,[self allProperties],NULL);
		[view updateLayout:&layout withBounds:view.bounds];
		
		viewInitialized = YES;
	}
	return view;
}

#pragma mark Layout 

-(void)layoutChild:(TiViewProxy*)child bounds:(CGRect)bounds
{
	if (view!=nil)
	{
		// layout out ourself
		UIView *childView = [child view];
	
		if ([childView superview]!=view)
		{
			[view addSubview:childView];
		}
		
		LayoutConstraint layout;
		ReadConstraintFromDictionary(&layout,[child allProperties],NULL);
		[[child view] updateLayout:&layout withBounds:bounds];
		
		// tell our children to also layout
		[child layoutChildren:childView.bounds];
	}
}

-(void)layoutChildren:(CGRect)bounds
{
	// now ask each of our children for their view
	for (id child in self.children)
	{
		[self layoutChild:child bounds:bounds];
	}
}

-(CGRect)appFrame
{
	return [[UIScreen mainScreen] applicationFrame];
}

#pragma mark Memory Management

-(void)didReceiveMemoryWarning:(NSNotification*)notification
{
	//FIXME - not sure this is the right thing to do but testing remove the view on demand
	if (view!=nil)
	{
		[view removeFromSuperview];
		RELEASE_TO_NIL(view);
	}
	[super didReceiveMemoryWarning:notification];
}

-(void)_destroy
{
	if (view!=nil)
	{
		[view removeFromSuperview];
		RELEASE_TO_NIL(view);
	}
	if (children!=nil)
	{
		[children removeAllObjects];
		RELEASE_TO_NIL(children);
	}
	[super _destroy];
}

-(void)destroy
{
	//FIXME- me already have a _destroy, refactor this
	[self _destroy];
}

#pragma mark Listener Management

-(void)_listenerAdded:(NSString*)type count:(int)count
{
	if (self.modelDelegate!=nil)
	{
		[self.modelDelegate listenerAdded:type count:count];
	}
}

-(void)_listenerRemoved:(NSString*)type count:(int)count
{
	if (self.modelDelegate!=nil)
	{
		[self.modelDelegate listenerRemoved:type count:count];
	}
}

#pragma mark Invocation

-(id)resultForUndefinedMethod:(NSString*)name args:(NSArray*)args
{
	// support dynamic forwarding to model delegate methods if attached
	if (self.modelDelegate!=nil)
	{
		NSString *methodSelectorName = [NSString stringWithFormat:@"%@:",name];
		SEL selector = NSSelectorFromString(methodSelectorName);
		if ([(NSObject*)self.modelDelegate respondsToSelector:selector])
		{
			if ([NSThread isMainThread])
			{
				[(NSObject*)self.modelDelegate performSelector:selector withObject:args];
			}
			else 
			{
				[(NSObject*)self.modelDelegate performSelectorOnMainThread:selector withObject:args waitUntilDone:NO];
			}
			return nil;
		}
	}
	return [super resultForUndefinedMethod:name args:args];
}

#pragma mark For Nav Bar Support

-(BOOL)supportsNavBarPositioning
{
	return NO;
}

-(UIBarButtonItem*)barButtonItem
{
	return nil;
}

-(void)removeNavBarButtonView
{
	// called to remove
}


@end