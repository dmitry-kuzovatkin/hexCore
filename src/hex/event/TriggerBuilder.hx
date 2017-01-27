package hex.event;

import haxe.macro.ComplexTypeTools;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.ClassField;
import haxe.macro.TypeTools;
import hex.error.PrivateConstructorException;
import hex.event.ITrigger;
import hex.util.MacroUtil;


using haxe.macro.Context;

/**
 * ...
 * @author Francis Bourre
 */
@:final 
class TriggerBuilder
{
	static var _cache : Map<String, TypeDefinition> = new Map();
	
	/** @private */
    function new()
    {
        throw new PrivateConstructorException( "This class can't be instantiated." );
    }
	
	static function _isOutput( f ) : Bool
	{
		switch ( f.kind )
		{
			case FProp( get, set, TPath( p ), e ):
				return MacroUtil.getClassFullQualifiedName( p ) == Type.getClassName( ITrigger );
				
			default:
				return false;
		}
	}
	
	macro static public function build() : Array<Field> 
	{
		var fields = Context.getBuildFields();

		if ( Context.getLocalClass().get().isInterface )
		{
			return fields;
		}
		
		for ( f in fields )
		{
			var isOutput = TriggerBuilder._isOutput( f );
			if ( isOutput ) 
			{
				switch( f.kind )
				{ 
					//TODO handle properties with virtual getters/setters
					case FVar( t, e ):
						
						Context.error( "'" + f.name + "' property is not public with read access only.\n Use 'public var " +
							f.name + " ( default, never )' with '@Trigger' annotation", f.pos );

					case FProp( get, set, t, e ):
						
						if ( get != "default" || set != "never" )
						{
							Context.error( "'" + f.name + "' property is not public with read access only.\n Use 'public var " +
							f.name + " ( default, never )' with '@Trigger' annotation", f.pos );
						}
						
						f.kind = _getKind( f, get, set );
						
					case _:
				}
			}
		}
		
        return fields;
    }
	
	static function _getKind( f, ?get, ?set )
	{
		var outputDefinition 	= TriggerBuilder._getOutputDefinition( f );
		var e 					= TriggerBuilder._buildClass( outputDefinition );
		var className 			= e.pack.join( '.' ) + '.' + e.name;
		var typePath 			= MacroUtil.getTypePath( className, f.pos );
		var complexType 		= TypeTools.toComplexType( Context.getType( className ) );
		
		return ( get == null && set == null ) ?
			FVar( complexType, { expr: MacroUtil.instantiate( typePath ), pos: f.pos } ):
			FProp( get, set, complexType, { expr: MacroUtil.instantiate( typePath ), pos: f.pos } );

	}
	
	static function _getOutputDefinition( f ) : { name: String, typePath : TypePath, paramComplexType : Null<ComplexType> }
	{
		var name 					: String 			= "";
		var connectionDefinition = null;
		
		//TODO DRY
		switch ( f.kind )
		{
			case FVar( TPath( p ), e ):

				TriggerBuilder._checkITriggerImplementation( f, p );
				connectionDefinition = TriggerBuilder._getConnectionDefinition( p.params );
				connectionDefinition.typePath = p;
				
				var t : haxe.macro.Type = Context.getType( p.pack.concat( [ p.name ] ).join( '.' ) );
				
				switch ( t )
				{
					case TInst( t, p ):
						var ct = t.get();
						name = ct.pack.concat( [ ct.name ] ).join( '.' );

					case _:
				}
			
			case FProp( get, set, TPath( p ), e ):
				
				TriggerBuilder._checkITriggerImplementation( f, p );
				connectionDefinition = TriggerBuilder._getConnectionDefinition( p.params );
				connectionDefinition.typePath = p;
				
				var t : haxe.macro.Type = Context.getType( p.pack.concat( [ p.name ] ).join( '.' ) );
				
				switch ( t )
				{
					case TInst( t, p ):
						var ct = t.get();
						name = ct.pack.concat( [ ct.name ] ).join( '.' );

					case _:
				}

			case _:
		}
		
		//TODO check double
		var tpName = connectionDefinition.fullyQualifiedName;
		if ( name != Type.getClassName( ITrigger ) )
		{
			Context.error( "'" + f.name + "' property should be typed '" + Type.getClassName( ITrigger ) + "<" + tpName 
				+ ">' instead of '" + name + "<" + tpName + ">'", f.pos );
		}
		
		return connectionDefinition;
	}
	
	static function _buildClass( interfaceName : { name: String, typePath : TypePath, paramComplexType : Null<ComplexType> } ) : { name: String, pack: Array<String> }
	{
		var className 	= '__Trigger_Class_For__' + interfaceName.name;
		var dispatcherClass : TypeDefinition = null;
		
		if ( !TriggerBuilder._cache.exists( className ) )
		{
			var complexType = interfaceName.paramComplexType;

			dispatcherClass = macro class $className
			{ 
				var _inputs : Array<$complexType>;
		
				public function new() 
				{
					this._inputs = [];
				}

				public function connect( input : $complexType ) : Bool
				{
					if ( this._inputs.indexOf( input ) == -1 )
					{
						this._inputs.push( input );
						return true;
					}
					else
					{
						return false;
					}
				}

				public function disconnect( input : $complexType ) : Bool
				{
					var index : Int = this._inputs.indexOf( input );
					
					if ( index > -1 )
					{
						this._inputs.splice( index, 1 );
						return true;
					}
					else
					{
						return false;
					}
				}
			};

			var newFields = dispatcherClass.fields;

			switch( ComplexTypeTools.toType( interfaceName.paramComplexType ) )
			{
				case TInst( _.get() => cls, params ):

					var fields : Array<ClassField> = cls.fields.get();

					for ( field in fields )
					{
						switch( field.kind )
						{
							case FMethod( k ):
								
								var fieldType 					= field.type;
								var ret : ComplexType 			= null;
								var args : Array<FunctionArg> 	= [];
							
								switch( fieldType )
								{
									case TFun( a, r ):
										
										ret = r.toComplexType();

										if ( a.length > 0 )
										{
											args = a.map( function( arg )
											{
												return cast { name: arg.name, type: arg.t.toComplexType(), opt: arg.opt };
											} );
										}
									
									case _:
								}

								var newField : Field = 
								{
									meta: field.meta.get(),
									name: field.name,
									pos: field.pos,
									kind: null,
									access: [ APublic ]
								}

								var methodName  = field.name;
								var methArgs = [ for ( arg in args ) macro $i { arg.name } ];
								var body = 
								macro 
								{
									for ( input in this._inputs ) input.$methodName( $a{ methArgs } );
								};
								
								
								newField.kind = FFun( 
									{
										args: args,
										ret: ret,
										expr: body
									}
								);
								
								newFields.push( newField );
								
							case _:
						}
					}

					case _:
			}
			
			var typePath 	: TypePath;
			var pack 		: Array<String>;
			
			switch( complexType )
			{
				case TPath( p ):
					var t = Context.getType( p.pack.concat( [ p.name ] ).join( '.' ) );

					switch ( t )
					{
						case TInst( t, p ):
							var ct = t.get();
							pack = ct.pack.copy();
							
						case _:
					}

					typePath = p;

					
				case _:
			}

			dispatcherClass.pack = pack;

			switch( dispatcherClass.kind )
			{
				case TDClass( superClass, interfaces, isInterface ):
					interfaces.push( typePath );
					//interfaces.push( interfaceName.typePath );
					interfaces.push( MacroUtil.getTypePath( Type.getClassName( ITrigger ), [ TPType( complexType ) ] ) );
					
				case _:
			}
			
			Context.defineType( dispatcherClass );
			TriggerBuilder._cache.set( className, dispatcherClass );
		}
		else
		{
			dispatcherClass = TriggerBuilder._cache.get( className );
		}
		
		return { name: dispatcherClass.name, pack: dispatcherClass.pack };
	}
	
	static function _checkITriggerImplementation( f, tp : TypePath ) : Void
	{
		var className = MacroUtil.getClassFullQualifiedName( tp );
		
		if ( className != Type.getClassName( ITrigger )  )
		{
			Context.error( "'" + f.name + "' property is not typed '" + Type.getClassName( ITrigger ) + "<ConnecttionType>'", f.pos );
		}
	}
	
	static function _getConnectionDefinition( params : Array<TypeParam> )
	{
		for ( param in params )
		{
			switch( param )
			{
				case TPType( tp ) :

					switch( tp )
					{
						case TPath( p ):
							var t = Context.getType( p.pack.concat( [ p.name ] ).join( '.' ) );
							switch ( t )
							{
								case TInst( t, p ):
									var ct = t.get();
									return { name: ct.name, fullyQualifiedName: ct.pack.concat( [ ct.name ] ).join( '.' ), paramComplexType: tp, typePath: null };
									
								case _:
							}
							
						case _:
					}
					
				case _:
				
			}
		}
		
		return null;
	}
}
